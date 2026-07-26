//! Relay-side implementation of [`ActionSink`] for workflow actions.
//!
//! Builds Nostr events, persists them, and delegates post-persist side effects
//! (WebSocket fan-out, Redis pub/sub, search indexing, audit logging) to the
//! existing [`dispatch_persistent_event`] helper.

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Weak};

use buzz_core::kind::{KIND_STREAM_MESSAGE, KIND_WORKFLOW_APPROVAL_REQUESTED};
use buzz_core::tenant::CommunityId;
use buzz_workflow::action_sink::{ActionSink, ActionSinkError, ApprovalReceipt, ApprovalRequest};
use chrono::Utc;
use nostr::{EventBuilder, Kind, Tag};
use sha2::{Digest as _, Sha256};
use tracing::info;
use uuid::Uuid;

use crate::handlers::event::dispatch_persistent_event;
use crate::state::AppState;

/// Resolves `@Name` mentions in workflow message text to the pubkeys of the
/// channel members they name, so the emitted kind:9 carries the `p` tags that
/// ACP agent-wake (`event_mentions_agent`) is gated on.
///
/// The client resolves mentions to `p` tags at compose time from an interactive
/// autocomplete pick; the workflow path has only free text, so this reverse-parse
/// *defines* the matching contract. It is deliberately conservative to avoid
/// waking the wrong agent:
///
/// - **Members only.** Candidates are the destination channel's members; global
///   users are never matched.
/// - **Exact display name.** No substring, prefix, or fuzzy matching. Names may
///   contain spaces/punctuation (`"Will Pfleger"`, `"Lep (Subagent)"`), so the
///   match is anchored on `@` and terminated by a non-name boundary rather than
///   whitespace.
/// - **Greedy-longest, non-overlapping.** Longer names are matched first and
///   consume their span, so `@Will Pfleger` binds *Pfleger* and a bare `@Will`
///   does not match the member `"Will Pfleger"`.
/// - **Ambiguous names wake no one.** If two or more members share the matched
///   display name, no `p` tag is emitted for it — arbitrary selection would
///   silently misroute and tagging all of them is a false-wake firehose.
///
/// Returns deduplicated pubkey hexes, in first-appearance order in `text`.
fn resolve_mention_pubkeys(text: &str, members: &[(String, String)]) -> Vec<String> {
    // Name → pubkey, folding case (client matches case-insensitively). A name
    // that maps to more than one distinct pubkey is ambiguous → wake no one.
    let mut by_name: std::collections::HashMap<String, Option<String>> =
        std::collections::HashMap::new();
    for (name, pubkey) in members {
        if name.trim().is_empty() {
            continue;
        }
        by_name
            .entry(name.to_lowercase())
            .and_modify(|slot| {
                if slot.as_deref() != Some(pubkey.as_str()) {
                    *slot = None; // ambiguous
                }
            })
            .or_insert_with(|| Some(pubkey.clone()));
    }

    // Match longest names first so a longer name consumes its span before a
    // shorter substring name can claim part of it.
    let mut names: Vec<&(String, String)> = members.iter().collect();
    names.sort_by_key(|(name, _)| std::cmp::Reverse(name.chars().count()));

    let chars: Vec<char> = text.chars().collect();
    let mut consumed = vec![false; chars.len()];

    // Case-insensitivity folds *both* sides through `char::to_lowercase`, which
    // can change length: `İ` (U+0130) lowercases to two code points (`i` +
    // U+0307 combining dot). Comparing a pre-lowercased copy of the whole text
    // against a lowercased name by index silently desyncs once any earlier char
    // expands. Instead, fold on the fly: walk the original `chars` at the
    // candidate `@`, folding each char, and match against the folded-name char
    // stream — tracking how many *original* chars were consumed so
    // boundary/`consumed` accounting stays in original coordinates. `None` = no
    // match; `Some(n)` = matched, consuming `n` original chars after the `@`.
    let match_name_len = |start: usize, folded_name: &[char]| -> Option<usize> {
        let mut ci = start;
        let mut ni = 0;
        while ni < folded_name.len() {
            let c = *chars.get(ci)?;
            for fc in c.to_lowercase() {
                if folded_name.get(ni) != Some(&fc) {
                    return None;
                }
                ni += 1;
            }
            ci += 1;
        }
        Some(ci - start)
    };

    // A mention is anchored on `@` at a left boundary (start / whitespace / `(`)
    // and the matched name must not be followed by a name-continuation char —
    // otherwise `@Will` would match inside `@Willow`. Combined with matching the
    // longest member name first, this is the whole rule: no punctuation allowlist
    // to get wrong, and it is unicode-safe (em-dash, emoji all terminate a name).
    let is_left_boundary = |i: usize| i == 0 || chars[i - 1].is_whitespace() || chars[i - 1] == '(';
    let extends_name = |c: char| c.is_alphanumeric() || c == '_';

    let mut out: Vec<String> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut hits: Vec<(usize, String)> = Vec::new();

    for (name, _) in &names {
        let folded_name: Vec<char> = name.to_lowercase().chars().collect();
        if folded_name.is_empty() {
            continue;
        }
        let mut at = 0;
        while at < chars.len() {
            // Anchor on `@` at a left boundary and an unconsumed span; only then
            // attempt the fold-match. `name_len` is measured in *original* chars,
            // so `at + 1 + name_len` is the true position just past the name.
            let name_len = (chars[at] == '@' && is_left_boundary(at) && !consumed[at])
                .then(|| match_name_len(at + 1, &folded_name))
                .flatten()
                .filter(|&n| {
                    chars[at + 1 + n..]
                        .first()
                        .is_none_or(|&c| !extends_name(c))
                });
            if let Some(name_len) = name_len {
                let span = 1 + name_len;
                if let Some(Some(pubkey)) = by_name.get(&name.to_lowercase()) {
                    hits.push((at, pubkey.clone()));
                }
                for slot in consumed.iter_mut().skip(at).take(span) {
                    *slot = true;
                }
                at += span;
            } else {
                at += 1;
            }
        }
    }

    hits.sort_by_key(|(at, _)| *at);
    for (_, pubkey) in hits {
        if seen.insert(pubkey.clone()) {
            out.push(pubkey);
        }
    }
    out
}

fn resolve_approver_pubkey(
    approver_spec: &str,
    candidates: &[(Option<String>, String)],
) -> Result<String, ActionSinkError> {
    let approver_spec = approver_spec.trim();
    if approver_spec.is_empty() {
        return Err(ActionSinkError::InvalidInput(
            "approval requires an exact human approver".into(),
        ));
    }

    if approver_spec.len() == 64 && approver_spec.chars().all(|c| c.is_ascii_hexdigit()) {
        let normalized = nostr::PublicKey::from_hex(approver_spec)
            .map_err(|e| ActionSinkError::InvalidInput(format!("invalid approver pubkey: {e}")))?
            .to_hex();
        return candidates
            .iter()
            .any(|(_, pubkey)| pubkey == &normalized)
            .then_some(normalized)
            .ok_or_else(|| {
                ActionSinkError::InvalidInput(
                    "approval target is not an active member of the workflow scope".into(),
                )
            });
    }

    let name = approver_spec
        .strip_prefix('@')
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .ok_or_else(|| {
            ActionSinkError::InvalidInput(
                "approver must be a 64-character pubkey or @display-name".into(),
            )
        })?;
    let mut matches = candidates
        .iter()
        .filter(|(display_name, _)| {
            display_name
                .as_deref()
                .is_some_and(|candidate| candidate.eq_ignore_ascii_case(name))
        })
        .map(|(_, pubkey)| pubkey.clone())
        .collect::<Vec<_>>();
    matches.sort();
    matches.dedup();

    match matches.as_slice() {
        [pubkey] => Ok(pubkey.clone()),
        [] => Err(ActionSinkError::InvalidInput(format!(
            "approver @{name} is not an active member of the workflow scope"
        ))),
        _ => Err(ActionSinkError::InvalidInput(format!(
            "approver @{name} is ambiguous in the workflow scope"
        ))),
    }
}

fn build_approval_request_event(
    relay_keys: &nostr::Keys,
    request: &ApprovalRequest,
    approver_pubkey: &str,
    token_digest: &str,
    requesting_agent: Option<&str>,
) -> Result<nostr::Event, ActionSinkError> {
    if request.message.trim().is_empty() {
        return Err(ActionSinkError::EmptyContent);
    }

    let mut tags = vec![
        Tag::parse(["d", token_digest])
            .map_err(|e| ActionSinkError::EventBuild(format!("d tag: {e}")))?,
        Tag::parse(["p", approver_pubkey])
            .map_err(|e| ActionSinkError::EventBuild(format!("p tag: {e}")))?,
        Tag::parse(["workflow", &request.workflow_id.to_string()])
            .map_err(|e| ActionSinkError::EventBuild(format!("workflow tag: {e}")))?,
        Tag::parse(["run", &request.run_id.to_string()])
            .map_err(|e| ActionSinkError::EventBuild(format!("run tag: {e}")))?,
        Tag::parse(["step", &request.step_id])
            .map_err(|e| ActionSinkError::EventBuild(format!("step tag: {e}")))?,
        Tag::parse(["expiration", &request.expires_at.timestamp().to_string()])
            .map_err(|e| ActionSinkError::EventBuild(format!("expiration tag: {e}")))?,
    ];
    if let Some(channel_id) = request.channel_id {
        tags.push(
            Tag::parse(["h", &channel_id.to_string()])
                .map_err(|e| ActionSinkError::EventBuild(format!("h tag: {e}")))?,
        );
    }
    if let Some(agent_pubkey) = requesting_agent {
        tags.push(
            Tag::parse(["agent", agent_pubkey])
                .map_err(|e| ActionSinkError::EventBuild(format!("agent tag: {e}")))?,
        );
    }

    EventBuilder::new(
        Kind::Custom(KIND_WORKFLOW_APPROVAL_REQUESTED as u16),
        &request.message,
    )
    .tags(tags)
    .sign_with_keys(relay_keys)
    .map_err(|e| ActionSinkError::EventBuild(format!("signing: {e}")))
}

/// Relay-side action sink — executes workflow side-effects directly.
///
/// Holds a **weak** reference to `AppState` to avoid an `Arc` reference cycle:
/// `AppState` → `WorkflowEngine` → `ActionSink` → `AppState`. Using `Weak`
/// breaks the cycle so all structs can be dropped on shutdown.
///
/// Post-persist side effects are delegated to [`dispatch_persistent_event`]
/// for consistency with the REST/WebSocket paths.
pub struct RelayActionSink {
    state: Weak<AppState>,
}

impl RelayActionSink {
    /// Create a new `RelayActionSink` from the shared application state.
    pub fn new(state: &Arc<AppState>) -> Self {
        Self {
            state: Arc::downgrade(state),
        }
    }
}

impl ActionSink for RelayActionSink {
    fn send_message(
        &self,
        community_id: CommunityId,
        channel_id: &str,
        text: &str,
        author_pubkey: &str,
    ) -> Pin<Box<dyn Future<Output = Result<String, ActionSinkError>> + Send + '_>> {
        let channel_id = channel_id.to_owned();
        let text = text.to_owned();
        let author_pubkey = author_pubkey.to_owned();

        Box::pin(async move {
            // 0. Upgrade weak reference — fails only during shutdown.
            let state = self
                .state
                .upgrade()
                .ok_or_else(|| ActionSinkError::Database("relay is shutting down".into()))?;

            // The run carries its owning community (`community_id`); the
            // relay-signed kind:9 message belongs to *that* community, never the
            // deployment default. Re-deriving the tenant from `config.relay_url`
            // would post a community-B workflow's output into the deployment/
            // default community under N>1. Read the community's host back to
            // form a complete TenantContext (host is for labelling only — the
            // community is already fixed and is never re-derived from it). Fail
            // closed if the community no longer maps to a host.
            let host = state
                .db
                .lookup_community_host(community_id)
                .await
                .map_err(|e| ActionSinkError::Database(e.to_string()))?
                .ok_or_else(|| {
                    ActionSinkError::Database(format!(
                        "workflow run community {community_id} is not mapped to a host"
                    ))
                })?;
            let tenant = buzz_core::tenant::TenantContext::resolved(community_id, host);

            // 1. Validate content is not empty/whitespace-only
            if text.trim().is_empty() {
                return Err(ActionSinkError::EmptyContent);
            }

            // 2. Parse and validate channel — canonicalize UUID immediately
            let channel_uuid = Uuid::parse_str(&channel_id)
                .map_err(|e| ActionSinkError::InvalidInput(format!("invalid UUID: {e}")))?;
            let channel_id_canonical = channel_uuid.to_string();

            let channel = state
                .db
                .get_channel(tenant.community(), channel_uuid)
                .await
                .map_err(|e| match &e {
                    buzz_db::DbError::ChannelNotFound(_) | buzz_db::DbError::NotFound(_) => {
                        ActionSinkError::ChannelNotFound(channel_id_canonical.clone())
                    }
                    _ => ActionSinkError::Database(e.to_string()),
                })?;

            if channel.archived_at.is_some() {
                return Err(ActionSinkError::ChannelArchived(
                    channel_id_canonical.clone(),
                ));
            }

            let author_pubkey = nostr::PublicKey::from_hex(&author_pubkey).map_err(|e| {
                ActionSinkError::InvalidInput(format!("invalid author pubkey: {e}"))
            })?;
            let author_pubkey_bytes = author_pubkey.to_bytes().to_vec();
            let author_pubkey_hex = author_pubkey.to_hex();
            let is_member = state
                .is_member_cached(tenant.community(), channel_uuid, &author_pubkey_bytes)
                .await
                .map_err(|e| ActionSinkError::Database(e.to_string()))?;
            if !is_member && channel.visibility != "open" {
                return Err(ActionSinkError::InvalidInput(
                    "workflow owner does not have access to destination channel".into(),
                ));
            }

            // 3. Build kind:9 Nostr event
            //    - Signed by relay keypair (event.pubkey = relay pubkey)
            //    - `p` tag attributes the message to the workflow owner
            //    - `h` tag scopes to the channel (NIP-29, canonical UUID)
            //    - `buzz:workflow` tag prevents recursive workflow triggering
            //    - one `p` tag per `@Name` that resolves to a channel member,
            //      so mentioned agents are woken (wake is `p`-tag gated)
            let mut tags = vec![
                Tag::parse(["p", &author_pubkey_hex])
                    .map_err(|e| ActionSinkError::EventBuild(format!("p tag: {e}")))?,
                Tag::parse(["h", &channel_id_canonical])
                    .map_err(|e| ActionSinkError::EventBuild(format!("h tag: {e}")))?,
                Tag::parse(["buzz:workflow", "true"])
                    .map_err(|e| ActionSinkError::EventBuild(format!("workflow tag: {e}")))?,
            ];

            // Resolve `@Name` mentions to channel-member pubkeys and append a
            // `p` tag for each (skipping the author, already tagged above). A
            // resolution failure must not drop the message, so log and proceed
            // with the base tags.
            let members = state
                .db
                .get_members(tenant.community(), channel_uuid)
                .await
                .map_err(|e| ActionSinkError::Database(e.to_string()))?;
            let member_pubkeys: Vec<Vec<u8>> = members.iter().map(|m| m.pubkey.clone()).collect();
            let users = state
                .db
                .get_users_bulk(tenant.community(), &member_pubkeys)
                .await
                .map_err(|e| ActionSinkError::Database(e.to_string()))?;
            let named_members: Vec<(String, String)> = users
                .into_iter()
                .filter_map(|u| {
                    let name = u.display_name?;
                    Some((name, nostr::PublicKey::from_slice(&u.pubkey).ok()?.to_hex()))
                })
                .collect();
            for mentioned in resolve_mention_pubkeys(&text, &named_members) {
                if mentioned == author_pubkey_hex {
                    continue;
                }
                tags.push(
                    Tag::parse(["p", &mentioned])
                        .map_err(|e| ActionSinkError::EventBuild(format!("mention p tag: {e}")))?,
                );
            }

            let kind = Kind::from(KIND_STREAM_MESSAGE as u16);
            let event = EventBuilder::new(kind, &text)
                .tags(tags)
                .sign_with_keys(&state.relay_keypair)
                .map_err(|e| ActionSinkError::EventBuild(format!("signing: {e}")))?;

            let event_id_hex = event.id.to_hex();
            let event_id_bytes = event.id.as_bytes().to_vec();
            let kind_u32 = KIND_STREAM_MESSAGE;

            let event_created_at = {
                let ts = event.created_at.as_secs() as i64;
                chrono::DateTime::from_timestamp(ts, 0).unwrap_or_else(Utc::now)
            };

            info!(
                event_id = %event_id_hex,
                channel_id = %channel_id_canonical,
                author = %author_pubkey,
                "Workflow SendMessage: posting kind {kind_u32} event"
            );

            // 4. Persist event with thread metadata (matches REST handler path).
            //    Workflow messages are always top-level: depth=0, no parent/root.
            let thread_meta = Some(buzz_db::event::ThreadMetadataParams {
                event_id: &event_id_bytes,
                event_created_at,
                channel_id: channel_uuid,
                parent_event_id: None,
                parent_event_created_at: None,
                root_event_id: None,
                root_event_created_at: None,
                depth: 0,
                broadcast: false,
            });

            let (stored_event, was_inserted) = state
                .db
                .insert_event_with_thread_metadata(
                    tenant.community(),
                    &event,
                    Some(channel_uuid),
                    thread_meta,
                )
                .await
                .map_err(|e| ActionSinkError::Database(e.to_string()))?;

            // 5. Post-persist side effects (fan-out, search, audit)
            //    Only if actually inserted (idempotency guard).
            if was_inserted {
                let _ = dispatch_persistent_event(
                    &tenant,
                    &state,
                    &stored_event,
                    kind_u32,
                    &author_pubkey_hex,
                    None,
                )
                .await;
            }

            Ok(event_id_hex)
        })
    }

    fn request_approval(
        &self,
        request: ApprovalRequest,
    ) -> Pin<Box<dyn Future<Output = Result<ApprovalReceipt, ActionSinkError>> + Send + '_>> {
        Box::pin(async move {
            let state = self
                .state
                .upgrade()
                .ok_or_else(|| ActionSinkError::Database("relay is shutting down".into()))?;

            let host = state
                .db
                .lookup_community_host(request.community_id)
                .await
                .map_err(|e| ActionSinkError::Database(e.to_string()))?
                .ok_or_else(|| {
                    ActionSinkError::Database(format!(
                        "workflow run community {} is not mapped to a host",
                        request.community_id
                    ))
                })?;
            let tenant = buzz_core::tenant::TenantContext::resolved(request.community_id, host);

            let owner_pubkey = nostr::PublicKey::from_hex(&request.owner_pubkey).map_err(|e| {
                ActionSinkError::InvalidInput(format!("invalid workflow owner pubkey: {e}"))
            })?;
            let owner_bytes = owner_pubkey.to_bytes().to_vec();
            let owner_hex = owner_pubkey.to_hex();

            let candidates = if let Some(channel_id) = request.channel_id {
                let channel = state
                    .db
                    .get_channel(request.community_id, channel_id)
                    .await
                    .map_err(|e| match e {
                        buzz_db::DbError::ChannelNotFound(_) | buzz_db::DbError::NotFound(_) => {
                            ActionSinkError::ChannelNotFound(channel_id.to_string())
                        }
                        other => ActionSinkError::Database(other.to_string()),
                    })?;
                if channel.archived_at.is_some() {
                    return Err(ActionSinkError::ChannelArchived(channel_id.to_string()));
                }
                let members = state
                    .db
                    .get_members(request.community_id, channel_id)
                    .await
                    .map_err(|e| ActionSinkError::Database(e.to_string()))?;
                let member_pubkeys = members
                    .iter()
                    .map(|member| member.pubkey.clone())
                    .collect::<Vec<_>>();
                let users = state
                    .db
                    .get_users_bulk(request.community_id, &member_pubkeys)
                    .await
                    .map_err(|e| ActionSinkError::Database(e.to_string()))?;
                let names = users
                    .into_iter()
                    .map(|user| (user.pubkey, user.display_name))
                    .collect::<std::collections::HashMap<_, _>>();
                members
                    .into_iter()
                    .filter_map(|member| {
                        let pubkey = nostr::PublicKey::from_slice(&member.pubkey).ok()?.to_hex();
                        let display_name = names.get(&member.pubkey).cloned().flatten();
                        Some((display_name, pubkey))
                    })
                    .collect::<Vec<_>>()
            } else {
                let members = state
                    .db
                    .list_relay_members(request.community_id)
                    .await
                    .map_err(|e| ActionSinkError::Database(e.to_string()))?;
                let parsed = members
                    .into_iter()
                    .filter_map(|member| {
                        let pubkey = nostr::PublicKey::from_hex(&member.pubkey).ok()?;
                        Some((pubkey.to_bytes().to_vec(), pubkey.to_hex()))
                    })
                    .collect::<Vec<_>>();
                let pubkeys = parsed
                    .iter()
                    .map(|(bytes, _)| bytes.clone())
                    .collect::<Vec<_>>();
                let users = state
                    .db
                    .get_users_bulk(request.community_id, &pubkeys)
                    .await
                    .map_err(|e| ActionSinkError::Database(e.to_string()))?;
                let names = users
                    .into_iter()
                    .map(|user| (user.pubkey, user.display_name))
                    .collect::<std::collections::HashMap<_, _>>();
                parsed
                    .into_iter()
                    .map(|(bytes, pubkey)| {
                        let display_name = names.get(&bytes).cloned().flatten();
                        (display_name, pubkey)
                    })
                    .collect::<Vec<_>>()
            };
            let approver_pubkey = resolve_approver_pubkey(&request.approver_spec, &candidates)?;

            let requesting_agent = state
                .db
                .get_agent_channel_policy(request.community_id, &owner_bytes)
                .await
                .map_err(|e| ActionSinkError::Database(e.to_string()))?
                .and_then(|(_, agent_owner)| agent_owner.map(|_| owner_hex.as_str()));

            let raw_token = Uuid::new_v4().to_string();
            let token_digest = hex::encode(Sha256::digest(raw_token.as_bytes()));
            let event = build_approval_request_event(
                &state.relay_keypair,
                &request,
                &approver_pubkey,
                &token_digest,
                requesting_agent,
            )?;
            let request_event_id = event.id.to_hex();

            let (stored_event, inserted) = state
                .db
                .create_actionable_approval(buzz_db::workflow::ActionableApprovalParams {
                    community_id: request.community_id,
                    raw_token: &raw_token,
                    workflow_id: request.workflow_id,
                    run_id: request.run_id,
                    step_id: &request.step_id,
                    step_index: request.step_index,
                    approver_spec: &approver_pubkey,
                    expires_at: request.expires_at,
                    request_event: &event,
                    channel_id: request.channel_id,
                    execution_trace: &request.execution_trace,
                })
                .await
                .map_err(|e| ActionSinkError::Database(e.to_string()))?;

            if inserted {
                let _ = dispatch_persistent_event(
                    &tenant,
                    &state,
                    &stored_event,
                    KIND_WORKFLOW_APPROVAL_REQUESTED,
                    &owner_hex,
                    None,
                )
                .await;
            }

            Ok(ApprovalReceipt { request_event_id })
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use buzz_workflow::ApprovalRequest;

    fn m(name: &str, pubkey: &str) -> (String, String) {
        (name.to_string(), pubkey.to_string())
    }

    // A 64-char hex pubkey built from a single repeated nibble, for readable tests.
    fn pk(nibble: char) -> String {
        std::iter::repeat_n(nibble, 64).collect()
    }

    fn approver(name: Option<&str>, nibble: char) -> (Option<String>, String) {
        (name.map(str::to_owned), pk(nibble))
    }

    fn approval_request() -> ApprovalRequest {
        ApprovalRequest {
            community_id: CommunityId::from_uuid(Uuid::from_u128(1)),
            workflow_id: Uuid::from_u128(2),
            run_id: Uuid::from_u128(3),
            step_id: "gate".to_owned(),
            step_index: 4,
            approver_spec: "@Aiden".to_owned(),
            message: "Ship the release?".to_owned(),
            expires_at: chrono::DateTime::from_timestamp(2_000_000_000, 0)
                .expect("valid timestamp"),
            channel_id: Some(Uuid::from_u128(5)),
            owner_pubkey: pk('c'),
            execution_trace: serde_json::json!([]),
        }
    }

    fn tag_values(event: &nostr::Event, name: &str) -> Vec<String> {
        event
            .tags
            .iter()
            .filter_map(|tag| {
                let values = tag.as_slice();
                (values.first().map(String::as_str) == Some(name))
                    .then(|| values.get(1).cloned())
                    .flatten()
            })
            .collect()
    }

    #[test]
    fn resolves_exact_human_approver_by_pubkey_or_unique_display_name() {
        let humans = vec![approver(Some("Aiden"), 'a'), approver(Some("Eva"), 'b')];

        assert_eq!(
            resolve_approver_pubkey(&pk('a'), &humans).expect("member pubkey"),
            pk('a')
        );
        assert_eq!(
            resolve_approver_pubkey("@aIdEn", &humans).expect("unique display name"),
            pk('a')
        );
    }

    #[test]
    fn approver_resolution_fails_closed_for_nonmember_or_ambiguous_name() {
        let humans = vec![approver(Some("Aiden"), 'a'), approver(Some("Aiden"), 'b')];

        assert!(matches!(
            resolve_approver_pubkey(&pk('c'), &humans),
            Err(ActionSinkError::InvalidInput(_))
        ));
        assert!(matches!(
            resolve_approver_pubkey("@Aiden", &humans),
            Err(ActionSinkError::InvalidInput(_))
        ));
    }

    #[test]
    fn approval_request_event_contains_only_public_action_coordinates() {
        let request = approval_request();
        let digest = pk('d');
        let requesting_agent = pk('e');
        let event = build_approval_request_event(
            &nostr::Keys::generate(),
            &request,
            &pk('a'),
            &digest,
            Some(&requesting_agent),
        )
        .expect("build request event");

        assert_eq!(event.kind.as_u16(), 46010);
        assert_eq!(event.content, "Ship the release?");
        assert_eq!(tag_values(&event, "d"), vec![digest]);
        assert_eq!(tag_values(&event, "p"), vec![pk('a')]);
        assert_eq!(
            tag_values(&event, "h"),
            vec![Uuid::from_u128(5).to_string()]
        );
        assert_eq!(
            tag_values(&event, "workflow"),
            vec![Uuid::from_u128(2).to_string()]
        );
        assert_eq!(
            tag_values(&event, "run"),
            vec![Uuid::from_u128(3).to_string()]
        );
        assert_eq!(tag_values(&event, "step"), vec!["gate".to_owned()]);
        assert_eq!(
            tag_values(&event, "expiration"),
            vec!["2000000000".to_owned()]
        );
        assert_eq!(tag_values(&event, "agent"), vec![requesting_agent]);
    }

    #[test]
    fn resolves_exact_member_name() {
        let members = vec![m("Robby", &pk('a'))];
        assert_eq!(
            resolve_mention_pubkeys("heads up @Robby — please take a look", &members),
            vec![pk('a')]
        );
    }

    #[test]
    fn matches_case_insensitively() {
        let members = vec![m("Robby", &pk('a'))];
        assert_eq!(
            resolve_mention_pubkeys("ping @robby", &members),
            vec![pk('a')]
        );
    }

    #[test]
    fn ignores_non_member_and_bare_at() {
        let members = vec![m("Robby", &pk('a'))];
        assert!(resolve_mention_pubkeys("hey @Stranger and @", &members).is_empty());
    }

    #[test]
    fn greedy_longest_binds_full_name_not_prefix() {
        // Both "Will" and "Will Pfleger" are members. `@Will Pfleger` must bind
        // Pfleger's key only; a bare `@Will` binds Will.
        let members = vec![m("Will", &pk('1')), m("Will Pfleger", &pk('2'))];
        assert_eq!(
            resolve_mention_pubkeys("cc @Will Pfleger on this", &members),
            vec![pk('2')]
        );
        assert_eq!(
            resolve_mention_pubkeys("cc @Will on this", &members),
            vec![pk('1')]
        );
    }

    #[test]
    fn at_mid_token_does_not_match() {
        // `@` must sit at a left boundary (start / whitespace / `(`). An email-ish
        // or mid-token `@` (`alice@Robby`) must not wake Robby.
        let members = vec![m("Robby", &pk('a'))];
        assert!(resolve_mention_pubkeys("alice@Robby", &members).is_empty());
    }

    #[test]
    fn prefix_member_does_not_match_inside_longer_word() {
        // "Sam" is a member; `@Sami` (no "Sami" member) must not wake Sam.
        let members = vec![m("Sam", &pk('3'))];
        assert!(resolve_mention_pubkeys("hi @Sami", &members).is_empty());
    }

    #[test]
    fn name_with_spaces_and_punctuation() {
        let members = vec![m("Lep (Subagent)", &pk('4'))];
        assert_eq!(
            resolve_mention_pubkeys("@Lep (Subagent) take it", &members),
            vec![pk('4')]
        );
    }

    #[test]
    fn em_dash_terminates_name() {
        // Generated prose often writes `@Name—text` with no space.
        let members = vec![m("Robby", &pk('a'))];
        assert_eq!(
            resolve_mention_pubkeys("@Robby—please look", &members),
            vec![pk('a')]
        );
    }

    #[test]
    fn non_ascii_member_name() {
        let members = vec![m("Zoë", &pk('5'))];
        assert_eq!(
            resolve_mention_pubkeys("welcome @Zoë!", &members),
            vec![pk('5')]
        );
    }

    #[test]
    fn lowercase_expansion_does_not_shift_later_mentions() {
        // Regression (Wren's redteam counterexample): `İ` (U+0130) lowercases to
        // TWO code points (`i` + U+0307). A design that pre-lowercases the whole
        // text and indexes it in parallel with the original chars desyncs after
        // the expansion, dropping every later valid mention. `@İ @Robby` must
        // resolve BOTH members, in order.
        let members = vec![m("İ", &pk('c')), m("Robby", &pk('a'))];
        assert_eq!(
            resolve_mention_pubkeys("@İ @Robby", &members),
            vec![pk('c'), pk('a')]
        );
    }

    #[test]
    fn sharp_s_matches_case_insensitively() {
        // `ẞ` (U+1E9E capital sharp s) lowercases to `ß` (U+00DF) — a single
        // char, NOT `ss` (that's uppercase/full-case-fold behavior, not
        // `char::to_lowercase`). Covers non-ASCII case-insensitive matching, and
        // that a later mention still resolves after it.
        let members = vec![m("ẞ", &pk('d')), m("Max", &pk('b'))];
        assert_eq!(
            resolve_mention_pubkeys("@ẞ and @Max", &members),
            vec![pk('d'), pk('b')]
        );
    }

    // Adversarial rows from Quinn's re-review (the two `ẞ→ss`-premised ones were
    // dropped as vacuous — `ẞ` lowercases to `ß`, one char, so it never inverts
    // original-vs-folded length; only `İ` does).

    #[test]
    fn combining_mark_in_name_matches() {
        // A name carrying a combining mark (`é` as `e` + U+0301) matches the same
        // sequence in text (1:1 folding) and terminates cleanly.
        let members = vec![m("Jos\u{0065}\u{0301}", &pk('4'))]; // "José" decomposed
        assert_eq!(
            resolve_mention_pubkeys("hi @Jos\u{0065}\u{0301}!", &members),
            vec![pk('4')]
        );
    }

    #[test]
    fn expanding_name_at_trailing_boundary() {
        // Expansion at the very end: `@İ` with nothing after must match, and
        // `@İx` (x extends the name, no `İx` member) must NOT match `İ`.
        let members = vec![m("İ", &pk('5'))];
        assert_eq!(resolve_mention_pubkeys("@İ", &members), vec![pk('5')]);
        assert!(resolve_mention_pubkeys("@İx", &members).is_empty());
    }

    #[test]
    fn back_to_back_at_is_one_mention() {
        // `@İ@Robby`: the second `@` is preceded by a name char (`İ`), so it is
        // NOT at a left boundary — same rule as `alice@Robby`. Back-to-back
        // `@a@b` is intentionally one mention; a separator is required to wake
        // both. The expanding first name (`İ` → 2 folded chars) also proves the
        // span accounting stays in original coordinates.
        let members = vec![m("İ", &pk('5')), m("Robby", &pk('a'))];
        assert_eq!(resolve_mention_pubkeys("@İ@Robby", &members), vec![pk('5')]);
        // ASCII control: same shape, same outcome — it's the boundary rule, not
        // a Unicode span-accounting bug.
        let ascii = vec![m("Sam", &pk('6')), m("Robby", &pk('a'))];
        assert_eq!(resolve_mention_pubkeys("@Sam@Robby", &ascii), vec![pk('6')]);
        // With a separator, both wake.
        assert_eq!(
            resolve_mention_pubkeys("@İ @Robby", &members),
            vec![pk('5'), pk('a')]
        );
    }

    #[test]
    fn ambiguous_name_wakes_no_one() {
        // Six "Fizz" agents (real team case) with distinct pubkeys → tag none.
        let members = vec![
            m("Fizz", &pk('6')),
            m("Fizz", &pk('7')),
            m("Fizz", &pk('8')),
        ];
        assert!(resolve_mention_pubkeys("@Fizz status?", &members).is_empty());
    }

    #[test]
    fn duplicate_name_same_pubkey_is_not_ambiguous() {
        // Same identity listed twice (e.g. two channels) is not a conflict.
        let members = vec![m("Fizz", &pk('6')), m("Fizz", &pk('6'))];
        assert_eq!(resolve_mention_pubkeys("@Fizz go", &members), vec![pk('6')]);
    }

    #[test]
    fn dedupes_repeated_mentions_in_first_appearance_order() {
        let members = vec![m("Robby", &pk('a')), m("Max", &pk('b'))];
        assert_eq!(
            resolve_mention_pubkeys("@Max then @Robby then @Max again", &members),
            vec![pk('b'), pk('a')]
        );
    }
}

#[cfg(test)]
mod integration_tests {
    //! Regression test for `e3661764` / `7899c1a8`: a workflow `send_message`
    //! that mentions a channel member by name (`@Name`) must emit a `p` tag for
    //! that member so ACP agent wake (`event_mentions_agent`, p-tag gated) fires.
    //!
    //! Postgres-gated like the other DB-backed relay tests. Run with:
    //!   `cargo test -p buzz-relay --lib workflow_sink -- --ignored`
    use super::*;
    use buzz_core::channel::{ChannelType, ChannelVisibility, MemberRole};
    use buzz_db::workflow::RunStatus;
    use buzz_db::CreateCommunityWithOwnerResult;
    use std::sync::Arc;

    /// Real-PG state mirroring `handlers::event::tests::test_state_with_redis_url`.
    async fn test_state() -> Arc<AppState> {
        let mut config = crate::config::Config::from_env().expect("default config loads");
        config.require_relay_membership = false;
        config.redis_url = "redis://127.0.0.1:1".to_string();
        let pool = sqlx::PgPool::connect_lazy(&config.database_url).expect("lazy pg pool");
        let db = buzz_db::Db::from_pool(pool.clone());
        let redis_pool = deadpool_redis::Config::from_url(&config.redis_url)
            .create_pool(Some(deadpool_redis::Runtime::Tokio1))
            .expect("redis pool");
        let pubsub = Arc::new(
            buzz_pubsub::PubSubManager::new(&config.redis_url, redis_pool.clone())
                .await
                .expect("pubsub manager"),
        );
        let audit = buzz_audit::AuditService::new(pool.clone());
        let auth = buzz_auth::AuthService::new(config.auth.clone());
        let search = buzz_search::SearchService::new(pool.clone());
        let workflow_engine = Arc::new(buzz_workflow::WorkflowEngine::new(
            db.clone(),
            buzz_workflow::WorkflowConfig::default(),
        ));
        let media_storage = buzz_media::MediaStorage::new(&config.media).expect("media storage");
        let (state, _audit_shutdown) = AppState::new(
            config,
            db,
            redis_pool,
            audit,
            pubsub,
            auth,
            search,
            workflow_engine,
            nostr::Keys::generate(),
            media_storage,
        );
        Arc::new(state)
    }

    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn workflow_send_message_p_tags_mentioned_member() {
        let state = test_state().await;

        let author = nostr::Keys::generate();
        let author_hex = author.public_key().to_hex();
        let agent = nostr::Keys::generate();
        let agent_hex = agent.public_key().to_hex();
        let agent_bytes = agent.public_key().to_bytes().to_vec();

        let host = format!("wf-ptag-{}.example", uuid::Uuid::new_v4().simple());
        let community = match state
            .db
            .create_community_with_owner(&host, &author_hex)
            .await
            .expect("create community")
        {
            CreateCommunityWithOwnerResult::Created(rec) => rec.id,
            other => panic!("expected fresh community, got {other:?}"),
        };

        // Open channel; the creator (author) is bootstrapped as an owner-member.
        let channel = state
            .db
            .create_channel(
                community,
                "wf-ptag",
                ChannelType::Stream,
                ChannelVisibility::Open,
                None,
                &author.public_key().to_bytes(),
                None,
            )
            .await
            .expect("create channel");

        // The mentioned agent is a real member with a resolvable display name.
        state
            .db
            .ensure_user(community, &agent_bytes)
            .await
            .expect("ensure agent user row");
        state
            .db
            .update_user_profile(community, &agent_bytes, Some("Robby"), None, None, None)
            .await
            .expect("set agent display name");
        state
            .db
            .add_member(
                community,
                channel.id,
                &agent_bytes,
                MemberRole::Bot,
                Some(&author.public_key().to_bytes()),
            )
            .await
            .expect("add agent member");

        let sink = RelayActionSink::new(&state);
        let event_id_hex = sink
            .send_message(
                community,
                &channel.id.to_string(),
                "heads up @Robby — please take a look",
                &author_hex,
            )
            .await
            .expect("send_message");

        let id_bytes = nostr::EventId::from_hex(&event_id_hex)
            .expect("event id")
            .as_bytes()
            .to_vec();
        let stored = state
            .db
            .get_event_by_id(community, &id_bytes)
            .await
            .expect("query event")
            .expect("event persisted");

        let p_tag_targets: Vec<&str> = stored
            .event
            .tags
            .iter()
            .filter(|t| t.as_slice().first().map(|s| s.as_str()) == Some("p"))
            .filter_map(|t| t.as_slice().get(1).map(|s| s.as_str()))
            .collect();

        assert!(
            p_tag_targets.contains(&author_hex.as_str()),
            "author should still be attributed via p tag; got {p_tag_targets:?}"
        );
        assert!(
            p_tag_targets.contains(&agent_hex.as_str()),
            "mentioned member {agent_hex} must be p-tagged so it wakes; got {p_tag_targets:?}"
        );
    }

    #[tokio::test]
    #[ignore = "requires Postgres"]
    async fn workflow_request_approval_persists_actionable_event_and_waiting_run() {
        let state = test_state().await;
        let owner = nostr::Keys::generate();
        let owner_hex = owner.public_key().to_hex();
        let approver = nostr::Keys::generate();
        let approver_bytes = approver.public_key().to_bytes().to_vec();

        let host = format!("wf-approval-{}.example", uuid::Uuid::new_v4().simple());
        let community = match state
            .db
            .create_community_with_owner(&host, &owner_hex)
            .await
            .expect("create community")
        {
            CreateCommunityWithOwnerResult::Created(record) => record.id,
            other => panic!("expected fresh community, got {other:?}"),
        };
        let channel = state
            .db
            .create_channel(
                community,
                "approvals",
                ChannelType::Stream,
                ChannelVisibility::Private,
                None,
                &owner.public_key().to_bytes(),
                None,
            )
            .await
            .expect("create channel");
        state
            .db
            .ensure_user(community, &approver_bytes)
            .await
            .expect("ensure approver");
        state
            .db
            .update_user_profile(community, &approver_bytes, Some("Aiden"), None, None, None)
            .await
            .expect("name approver");
        state
            .db
            .add_member(
                community,
                channel.id,
                &approver_bytes,
                MemberRole::Member,
                Some(&owner.public_key().to_bytes()),
            )
            .await
            .expect("add approver");

        let workflow_id = state
            .db
            .create_workflow(
                community,
                Some(channel.id),
                &owner.public_key().to_bytes(),
                "release approval",
                r#"{"trigger":{"on":"schedule"},"steps":[]}"#,
                &[7; 32],
            )
            .await
            .expect("create workflow");
        let run_id = state
            .db
            .create_workflow_run(community, workflow_id, None, None)
            .await
            .expect("create run");
        state
            .db
            .update_workflow_run(
                community,
                run_id,
                RunStatus::Running,
                0,
                &serde_json::json!([]),
                None,
            )
            .await
            .expect("start run");

        let sink = RelayActionSink::new(&state);
        let receipt = sink
            .request_approval(ApprovalRequest {
                community_id: community,
                workflow_id,
                run_id,
                step_id: "gate".to_owned(),
                step_index: 0,
                approver_spec: "@Aiden".to_owned(),
                message: "Ship the release?".to_owned(),
                expires_at: Utc::now() + chrono::Duration::hours(1),
                channel_id: Some(channel.id),
                owner_pubkey: owner_hex,
                execution_trace: serde_json::json!([]),
            })
            .await
            .expect("request approval");

        let event_id = nostr::EventId::from_hex(&receipt.request_event_id).expect("event id");
        let stored = state
            .db
            .get_event_by_id(community, event_id.as_bytes())
            .await
            .expect("query request")
            .expect("request persisted");
        let digest = stored
            .event
            .tags
            .iter()
            .find_map(|tag| {
                let values = tag.as_slice();
                (values.first().map(String::as_str) == Some("d"))
                    .then(|| values.get(1).cloned())
                    .flatten()
            })
            .expect("approval digest");
        let approval = state
            .db
            .get_approval_by_stored_hash(community, &hex::decode(digest).expect("digest hex"))
            .await
            .expect("approval row");
        assert_eq!(approval.approver_spec, approver.public_key().to_hex());
        assert_eq!(
            approval.request_event_id.as_deref(),
            Some(event_id.as_bytes().as_slice())
        );
        assert_eq!(
            state
                .db
                .get_workflow_run(community, run_id)
                .await
                .expect("waiting run")
                .status,
            RunStatus::WaitingApproval
        );
    }
}
