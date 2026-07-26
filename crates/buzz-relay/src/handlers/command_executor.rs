//! Command executor — transactional event processing for command kinds.
//!
//! Command kinds (41010–41012, 30620, 46020, 46030–46032) are processed
//! transactionally: validate → begin tx → insert event → execute mutations → commit.
//!
//! SECURITY: This module is only reachable AFTER the ingest pipeline has verified:
//! 1. Event signature (verify_event)
//! 2. Timestamp freshness (±15 min)
//! 3. Pubkey/auth identity match
//! 4. Per-kind scope authorization

use std::sync::Arc;

use chrono::Utc;
use nostr::{Event, EventBuilder, Kind, Tag};
use sha2::{Digest, Sha256};
use tracing::warn;
use uuid::Uuid;

use buzz_core::kind::*;
use buzz_core::tenant::{CommunityId, TenantContext};
use buzz_db::workflow::{
    ApprovalDecision, ApprovalDecisionOutcome, ApprovalDecisionParams, ApprovalRecord,
    ApprovalStatus, RunStatus,
};
use buzz_db::DbError;
use buzz_workflow::executor::TriggerContext;

use crate::state::AppState;
use crate::webhook_secret;

use super::event::dispatch_persistent_event;
use super::ingest::{extract_channel_id, IngestAuth, IngestError, IngestResult};
use super::side_effects::{
    emit_group_discovery_events, emit_membership_notification, emit_system_message,
    publish_dm_visibility_snapshot,
};

/// Route a command-kind event to the appropriate handler.
pub async fn handle_command(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: Event,
    auth: IngestAuth,
) -> Result<IngestResult, IngestError> {
    // Ensure the authenticated user exists in the users table (foreign key requirement).
    // The old REST handlers did this via extract_auth_context; command executor must do it explicitly.
    let pubkey_bytes = auth.pubkey().to_bytes().to_vec();
    match state
        .db
        .ensure_user(tenant.community(), &pubkey_bytes)
        .await
    {
        Ok(true) => {
            metrics::counter!(
                "buzz_users_created_total",
                "community" => tenant.host().to_owned()
            )
            .increment(1);
        }
        Ok(false) => {}
        Err(e) => {
            tracing::warn!("command_executor: ensure_user failed: {e}");
        }
    }

    let kind = event.kind.as_u16() as u32;
    match kind {
        KIND_DM_OPEN => handle_dm_open(tenant, state, &event, &auth).await,
        KIND_DM_ADD_MEMBER => handle_dm_add_member(tenant, state, &event, &auth).await,
        KIND_DM_HIDE => handle_dm_hide(tenant, state, &event, &auth).await,
        KIND_WORKFLOW_DEF => handle_workflow_def(tenant, state, &event, &auth).await,
        KIND_WORKFLOW_TRIGGER => handle_workflow_trigger(tenant, state, &event, &auth).await,
        KIND_APPROVAL_GRANT => handle_approval_grant(tenant, state, &event, &auth).await,
        KIND_APPROVAL_DENY => handle_approval_deny(tenant, state, &event, &auth).await,
        KIND_APPROVAL_PASS => handle_approval_pass(tenant, state, &event, &auth).await,
        _ => Err(IngestError::Rejected(format!(
            "unknown command kind: {kind}"
        ))),
    }
}

/// Result of persisting a command event: either a duplicate (already processed)
/// or an open transaction that the handler must commit after executing mutations.
enum PersistResult {
    /// Event was already processed — return idempotent success.
    Duplicate,
    /// Event inserted — transaction is open, handler must commit after mutations.
    Inserted(sqlx::Transaction<'static, sqlx::Postgres>),
}

/// Persist a command event inside a transaction. Returns the OPEN transaction
/// as an idempotency guard — if the event was already stored, `Duplicate` is
/// returned and the handler skips execution.
///
/// If the event is a duplicate (ON CONFLICT DO NOTHING), the transaction is
/// rolled back and `PersistResult::Duplicate` is returned — no mutations needed.
///
/// NOTE: Domain mutations (open_dm, upsert_workflow, etc.) execute on the
/// connection pool, NOT inside this transaction. The pattern is idempotent but
/// not strictly atomic: if a mutation succeeds but commit fails, the mutation
/// persists without the event record. On retry, the event INSERT succeeds
/// (no conflict), and the mutation re-executes — which is safe for idempotent
/// operations (open_dm, hide_dm, upsert_workflow). Approval decisions use the
/// stricter `buzz-db` decision transaction instead.
async fn persist_command_event(
    state: &Arc<AppState>,
    tenant: &TenantContext,
    event: &Event,
    channel_id_override: Option<Uuid>,
) -> Result<PersistResult, IngestError> {
    let channel_id = channel_id_override.or_else(|| extract_channel_id(event));

    let mut tx = state
        .db
        .begin_transaction()
        .await
        .map_err(|e| IngestError::Internal(format!("error: begin transaction: {e}")))?;

    // INSERT with ON CONFLICT DO NOTHING — idempotency guard.
    let id_bytes = event.id.as_bytes();
    let pubkey_bytes = event.pubkey.to_bytes();
    let sig_bytes = event.sig.serialize();
    let tags_json = serde_json::to_value(&event.tags)
        .map_err(|e| IngestError::Internal(format!("error: serialize tags: {e}")))?;
    let kind_i32 = event.kind.as_u16() as i32;
    let created_at_secs = event.created_at.as_secs() as i64;
    let created_at = chrono::DateTime::from_timestamp(created_at_secs, 0).ok_or_else(|| {
        IngestError::Rejected(format!("invalid: bad timestamp {created_at_secs}"))
    })?;
    let received_at = chrono::Utc::now();

    // Extract d_tag for parameterized replaceable kinds (NIP-33).
    let d_tag = buzz_db::event::extract_d_tag(event);
    if let Some(ref d_tag) = d_tag {
        if d_tag.len() > buzz_db::event::D_TAG_MAX_LEN {
            return Err(IngestError::Rejected(format!(
                "invalid: d tag too long ({} bytes, max {})",
                d_tag.len(),
                buzz_db::event::D_TAG_MAX_LEN,
            )));
        }

        // Command kinds normally use plain insert semantics, but workflow
        // definitions are NIP-33 events. Serialize writers for the same
        // coordinate and reject stale writes before executing the domain
        // mutation, otherwise old updates can overwrite newer workflow state.
        let lock_key = {
            let mut h: u64 = 0xcbf29ce484222325;
            for b in tenant.community().as_uuid().as_bytes() {
                h ^= *b as u64;
                h = h.wrapping_mul(0x100000001b3);
            }
            for b in kind_i32.to_le_bytes() {
                h ^= b as u64;
                h = h.wrapping_mul(0x100000001b3);
            }
            for b in pubkey_bytes.as_slice() {
                h ^= *b as u64;
                h = h.wrapping_mul(0x100000001b3);
            }
            for b in d_tag.as_bytes() {
                h ^= *b as u64;
                h = h.wrapping_mul(0x100000001b3);
            }
            h as i64
        };

        sqlx::query("SELECT pg_advisory_xact_lock($1)")
            .bind(lock_key)
            .execute(tx.as_mut())
            .await
            .map_err(|e| IngestError::Internal(format!("error: lock event coordinate: {e}")))?;

        let existing: Option<(chrono::DateTime<chrono::Utc>, Vec<u8>)> = sqlx::query_as(
            "SELECT created_at, id FROM events \
             WHERE community_id = $1 AND kind = $2 AND pubkey = $3 AND d_tag = $4 AND deleted_at IS NULL \
             ORDER BY created_at DESC, id ASC LIMIT 1",
        )
        .bind(tenant.community().as_uuid())
        .bind(kind_i32)
        .bind(pubkey_bytes.as_slice())
        .bind(d_tag)
        .fetch_optional(tx.as_mut())
        .await
        .map_err(|e| IngestError::Internal(format!("error: query event coordinate: {e}")))?;

        let incoming_id = event.id.as_bytes().as_slice();
        if let Some((existing_ts, existing_id)) = existing {
            let dominated = created_at < existing_ts
                || (created_at == existing_ts && incoming_id >= existing_id.as_slice());
            if dominated {
                return Ok(PersistResult::Duplicate);
            }

            sqlx::query(
                "UPDATE events SET deleted_at = NOW() \
                 WHERE community_id = $1 AND kind = $2 AND pubkey = $3 AND d_tag = $4 AND deleted_at IS NULL",
            )
            .bind(tenant.community().as_uuid())
            .bind(kind_i32)
            .bind(pubkey_bytes.as_slice())
            .bind(d_tag)
            .execute(tx.as_mut())
            .await
            .map_err(|e| IngestError::Internal(format!("error: replace old event: {e}")))?;
        }
    }

    let result = sqlx::query(
        r#"
        INSERT INTO events (community_id, id, pubkey, created_at, kind, tags, content, sig, received_at, channel_id, d_tag)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        ON CONFLICT DO NOTHING
        "#,
    )
    .bind(tenant.community().as_uuid())
    .bind(id_bytes.as_slice())
    .bind(pubkey_bytes.as_slice())
    .bind(created_at)
    .bind(kind_i32)
    .bind(&tags_json)
    .bind(&event.content)
    .bind(sig_bytes.as_slice())
    .bind(received_at)
    .bind(channel_id)
    .bind(d_tag.as_deref())
    .execute(tx.as_mut())
    .await
    .map_err(|e| IngestError::Internal(format!("error: insert event: {e}")))?;

    if result.rows_affected() == 0 {
        // Duplicate — rollback (implicit on drop) and signal idempotent success.
        Ok(PersistResult::Duplicate)
    } else {
        Ok(PersistResult::Inserted(tx))
    }
}

/// Extract all `p` tag values (hex pubkeys) from an event.
fn extract_p_tags(event: &Event) -> Vec<String> {
    event
        .tags
        .iter()
        .filter_map(|t| {
            if t.kind().to_string() == "p" {
                t.content().map(|s| s.to_string())
            } else {
                None
            }
        })
        .collect()
}

fn extract_pass_target(event: &Event) -> Result<Vec<u8>, IngestError> {
    let targets = extract_p_tags(event);
    let [target] = targets.as_slice() else {
        return Err(IngestError::Rejected(
            "invalid: approval pass requires exactly one p target".into(),
        ));
    };
    let pubkey = nostr::PublicKey::from_hex(target)
        .map_err(|_| IngestError::Rejected("invalid: bad approval pass target pubkey".into()))?;
    Ok(pubkey.to_bytes().to_vec())
}

fn validate_pass_target_policy(
    actor: &[u8],
    requester: Option<&[u8]>,
    target: &[u8],
    is_channel_member: bool,
    agent_owner: Option<&[u8]>,
    invocation_policy: &str,
    presence: Option<&str>,
) -> Result<(), IngestError> {
    if actor == target {
        return Err(IngestError::Rejected(
            "invalid: cannot pass an approval to yourself".into(),
        ));
    }
    if requester.is_some_and(|requester| requester == target) {
        return Err(IngestError::Rejected(
            "invalid: cannot pass an approval back to its requesting agent".into(),
        ));
    }
    if !is_channel_member {
        return Err(IngestError::Rejected(
            "forbidden: target agent is not an active channel member".into(),
        ));
    }
    let Some(agent_owner) = agent_owner else {
        return Err(IngestError::Rejected(
            "invalid: approval pass target is not a registered agent".into(),
        ));
    };
    match invocation_policy {
        "anyone" => {}
        "owner_only" if actor == agent_owner => {}
        "owner_only" => {
            return Err(IngestError::Rejected(
                "forbidden: only the target agent owner may invoke it".into(),
            ));
        }
        "nobody" => {
            return Err(IngestError::Rejected(
                "forbidden: target agent does not accept invocations".into(),
            ));
        }
        _ => {
            return Err(IngestError::Rejected(
                "forbidden: target agent has an unsupported invocation policy".into(),
            ));
        }
    }
    if !matches!(presence, Some("online" | "away")) {
        return Err(IngestError::Rejected(
            "invalid: target agent is offline".into(),
        ));
    }
    Ok(())
}

/// Extract the first `h` tag value (channel UUID) from an event.
fn extract_h_tag(event: &Event) -> Option<String> {
    event.tags.iter().find_map(|t| {
        if t.kind().to_string() == "h" {
            t.content().map(|s| s.to_string())
        } else {
            None
        }
    })
}

/// Extract the first `d` tag value from an event.
fn extract_d_tag(event: &Event) -> Option<String> {
    event.tags.iter().find_map(|t| {
        if t.kind().to_string() == "d" {
            t.content().map(|s| s.to_string())
        } else {
            None
        }
    })
}

/// Extract the first `e` tag value from an event.
fn extract_e_tag(event: &Event) -> Option<String> {
    event.tags.iter().find_map(|t| {
        if t.kind().to_string() == "e" {
            t.content().map(|s| s.to_string())
        } else {
            None
        }
    })
}

/// Extract a tag value by name.
fn extract_tag(event: &Event, tag_name: &str) -> Option<String> {
    event.tags.iter().find_map(|t| {
        if t.kind().to_string() == tag_name {
            t.content().map(|s| s.to_string())
        } else {
            None
        }
    })
}

/// Decode a hex pubkey string to 32 bytes.
fn decode_pubkey(hex_str: &str) -> Result<Vec<u8>, IngestError> {
    let bytes = hex::decode(hex_str)
        .map_err(|_| IngestError::Rejected(format!("invalid: bad pubkey hex: {hex_str}")))?;
    if bytes.len() != 32 {
        return Err(IngestError::Rejected(format!(
            "invalid: pubkey must be 32 bytes: {hex_str}"
        )));
    }
    Ok(bytes)
}

/// Compute SHA-256 hash of a string, returning raw bytes.
fn compute_definition_hash(json_str: &str) -> Vec<u8> {
    Sha256::digest(json_str.as_bytes()).to_vec()
}

async fn handle_dm_open(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    auth: &IngestAuth,
) -> Result<IngestResult, IngestError> {
    let self_bytes = auth.pubkey().to_bytes().to_vec();
    let self_hex = hex::encode(&self_bytes);

    // 1. Extract participant pubkeys from `p` tags
    let p_tags = extract_p_tags(event);

    // 2. Validate: at least 1 other participant, max 8 others (9 total)
    if p_tags.is_empty() {
        return Err(IngestError::Rejected(
            "invalid: pubkeys must contain at least 1 other participant".into(),
        ));
    }
    if p_tags.len() > 8 {
        return Err(IngestError::Rejected(
            "invalid: pubkeys may contain at most 8 other participants (9 total)".into(),
        ));
    }

    // Decode all provided pubkeys
    let mut other_bytes: Vec<Vec<u8>> = Vec::with_capacity(p_tags.len());
    for hex_str in &p_tags {
        other_bytes.push(decode_pubkey(hex_str)?);
    }

    // 3. Build full participant set (self + others, deduplicated)
    let mut all_bytes: Vec<Vec<u8>> = vec![self_bytes.clone()];
    for ob in &other_bytes {
        if !all_bytes.iter().any(|b| b == ob) {
            all_bytes.push(ob.clone());
        }
    }

    // Persist the command event (idempotency) — returns open transaction
    let tx = match persist_command_event(state, tenant, event, None).await? {
        PersistResult::Duplicate => {
            return Ok(IngestResult {
                event_id: event.id.to_hex(),
                accepted: true,
                message: "duplicate: already processed".into(),
            });
        }
        PersistResult::Inserted(tx) => tx,
    };

    // 4. Execute: open_dm
    let all_refs: Vec<&[u8]> = all_bytes.iter().map(|b| b.as_slice()).collect();
    let (channel, was_created) = state
        .db
        .open_dm(tenant.community(), &all_refs, &self_bytes)
        .await
        .map_err(|e| IngestError::Internal(format!("error: db open_dm: {e}")))?;

    // Commit: event + mutation succeeded atomically.
    tx.commit()
        .await
        .map_err(|e| IngestError::Internal(format!("error: commit transaction: {e}")))?;

    // 5. Side effects if newly created (post-commit, best-effort)
    if was_created {
        metrics::counter!(
            "buzz_channels_created_total",
            "community" => tenant.host().to_owned(),
            "type" => "dm"
        )
        .increment(1);

        // Invalidate caches for all participants
        for pk in &all_bytes {
            state.invalidate_membership(tenant, channel.id, pk);
        }

        let participant_hexes: Vec<String> = all_bytes.iter().map(hex::encode).collect();
        if let Err(e) = emit_system_message(
            tenant,
            state,
            channel.id,
            serde_json::json!({
                "type": "dm_created",
                "actor": self_hex,
                "participants": participant_hexes,
            }),
        )
        .await
        {
            warn!("DM open: system message failed: {e}");
        }

        if let Err(e) = emit_group_discovery_events(tenant, state, channel.id).await {
            warn!(channel = %channel.id, "DM open: discovery emission failed: {e}");
        }

        for participant in &all_bytes {
            if let Err(e) = emit_membership_notification(
                tenant,
                state,
                channel.id,
                participant,
                &self_bytes,
                KIND_MEMBER_ADDED_NOTIFICATION,
            )
            .await
            {
                warn!("DM open: membership notification failed: {e}");
            }
        }
    } else {
        // Re-open of an existing DM cleared the caller's hidden_at; refresh
        // their NIP-DV snapshot so the DM reappears in the sidebar.
        if let Err(e) = publish_dm_visibility_snapshot(tenant, state, &self_bytes).await {
            warn!("DM re-open: visibility snapshot failed: {e}");
        }
    }

    // 6. Return response
    Ok(IngestResult {
        event_id: event.id.to_hex(),
        accepted: true,
        message: format!(
            "response:{}",
            serde_json::json!({
                "channel_id": channel.id.to_string(),
                "created": was_created,
            })
        ),
    })
}

async fn handle_dm_add_member(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    auth: &IngestAuth,
) -> Result<IngestResult, IngestError> {
    let self_bytes = auth.pubkey().to_bytes().to_vec();

    // 1. Extract target channel from `h` tag, new member pubkeys from `p` tags
    let channel_id_str = extract_h_tag(event)
        .ok_or_else(|| IngestError::Rejected("invalid: missing h tag (channel_id)".into()))?;
    let channel_id = Uuid::parse_str(&channel_id_str)
        .map_err(|_| IngestError::Rejected("invalid: bad channel_id format".into()))?;

    let p_tags = extract_p_tags(event);
    if p_tags.is_empty() {
        return Err(IngestError::Rejected(
            "invalid: must specify at least 1 new participant in p tags".into(),
        ));
    }

    // 2. Validate caller is member of existing DM
    let is_member = state
        .is_member_cached(tenant.community(), channel_id, &self_bytes)
        .await
        .map_err(|e| IngestError::Internal(format!("error: membership check: {e}")))?;
    if !is_member {
        return Err(IngestError::Rejected(
            "forbidden: not a member of this DM".into(),
        ));
    }

    // 3. Validate channel is type "dm"
    let existing_channel = state
        .db
        .get_channel(tenant.community(), channel_id)
        .await
        .map_err(|_| IngestError::Rejected("invalid: DM not found".into()))?;
    if existing_channel.channel_type != "dm" {
        return Err(IngestError::Rejected("invalid: channel is not a DM".into()));
    }

    // 4. Get existing members, merge with new
    let existing_members = state
        .db
        .get_members(tenant.community(), channel_id)
        .await
        .map_err(|e| IngestError::Internal(format!("error: get members: {e}")))?;

    let mut all_bytes: Vec<Vec<u8>> = existing_members.into_iter().map(|m| m.pubkey).collect();

    // Decode and merge new pubkeys
    for hex_str in &p_tags {
        let bytes = decode_pubkey(hex_str)?;
        if !all_bytes.iter().any(|b| b == &bytes) {
            all_bytes.push(bytes);
        }
    }

    // 5. Enforce max 9 participants
    if all_bytes.len() > 9 {
        return Err(IngestError::Rejected(
            "invalid: DM supports at most 9 participants".into(),
        ));
    }

    // Persist the command event — returns open transaction
    let tx = match persist_command_event(state, tenant, event, None).await? {
        PersistResult::Duplicate => {
            return Ok(IngestResult {
                event_id: event.id.to_hex(),
                accepted: true,
                message: "duplicate: already processed".into(),
            });
        }
        PersistResult::Inserted(tx) => tx,
    };

    // 6. Execute: open_dm with expanded set (creates NEW DM — DM sets are immutable)
    let all_refs: Vec<&[u8]> = all_bytes.iter().map(|b| b.as_slice()).collect();
    let (new_channel, was_created) = state
        .db
        .open_dm(tenant.community(), &all_refs, &self_bytes)
        .await
        .map_err(|e| IngestError::Internal(format!("error: db open_dm: {e}")))?;

    // Commit: event + mutation succeeded atomically.
    tx.commit()
        .await
        .map_err(|e| IngestError::Internal(format!("error: commit transaction: {e}")))?;

    // 7. Cache invalidation + notifications for new DM (post-commit, best-effort)
    if was_created {
        metrics::counter!(
            "buzz_channels_created_total",
            "community" => tenant.host().to_owned(),
            "type" => "dm"
        )
        .increment(1);

        for pk in &all_bytes {
            state.invalidate_membership(tenant, new_channel.id, pk);
        }

        if let Err(e) = emit_group_discovery_events(tenant, state, new_channel.id).await {
            warn!(channel = %new_channel.id, "DM add_member: discovery emission failed: {e}");
        }

        for participant_bytes in &all_bytes {
            if let Err(e) = emit_membership_notification(
                tenant,
                state,
                new_channel.id,
                participant_bytes,
                &self_bytes,
                KIND_MEMBER_ADDED_NOTIFICATION,
            )
            .await
            {
                warn!("DM add_member: membership notification failed: {e}");
            }
        }
    }

    // 8. Return response
    Ok(IngestResult {
        event_id: event.id.to_hex(),
        accepted: true,
        message: format!(
            "response:{}",
            serde_json::json!({
                "channel_id": new_channel.id.to_string(),
            })
        ),
    })
}

async fn handle_dm_hide(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    auth: &IngestAuth,
) -> Result<IngestResult, IngestError> {
    let self_bytes = auth.pubkey().to_bytes().to_vec();

    // 1. Extract channel from `h` tag
    let channel_id_str = extract_h_tag(event)
        .ok_or_else(|| IngestError::Rejected("invalid: missing h tag (channel_id)".into()))?;
    let channel_id = Uuid::parse_str(&channel_id_str)
        .map_err(|_| IngestError::Rejected("invalid: bad channel_id format".into()))?;

    // 2. Validate caller is member of the DM
    let is_member = state
        .is_member_cached(tenant.community(), channel_id, &self_bytes)
        .await
        .map_err(|e| IngestError::Internal(format!("error: membership check: {e}")))?;
    if !is_member {
        return Err(IngestError::Rejected(
            "forbidden: not a member of this DM".into(),
        ));
    }

    // 3. Validate channel is type "dm"
    let channel = state
        .db
        .get_channel(tenant.community(), channel_id)
        .await
        .map_err(|_| IngestError::Rejected("invalid: DM not found".into()))?;
    if channel.channel_type != "dm" {
        return Err(IngestError::Rejected("invalid: channel is not a DM".into()));
    }

    // Persist the command event — returns open transaction
    let tx = match persist_command_event(state, tenant, event, None).await? {
        PersistResult::Duplicate => {
            return Ok(IngestResult {
                event_id: event.id.to_hex(),
                accepted: true,
                message: "duplicate: already processed".into(),
            });
        }
        PersistResult::Inserted(tx) => tx,
    };

    // 4. Execute: hide_dm
    state
        .db
        .hide_dm(tenant.community(), channel_id, &self_bytes)
        .await
        .map_err(|e| IngestError::Internal(format!("error: db hide_dm: {e}")))?;

    // Commit: event + mutation succeeded atomically.
    tx.commit()
        .await
        .map_err(|e| IngestError::Internal(format!("error: commit transaction: {e}")))?;

    // 5. Side effect (post-commit, best-effort): refresh the caller's NIP-DV
    // visibility snapshot so clients can filter this DM out of the sidebar.
    if let Err(e) = publish_dm_visibility_snapshot(tenant, state, &self_bytes).await {
        warn!("DM hide: visibility snapshot failed: {e}");
    }

    // 6. Return response
    Ok(IngestResult {
        event_id: event.id.to_hex(),
        accepted: true,
        message: "{}".into(),
    })
}

async fn handle_workflow_def(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    auth: &IngestAuth,
) -> Result<IngestResult, IngestError> {
    let self_bytes = auth.pubkey().to_bytes().to_vec();

    // 1. Extract channel and the canonical workflow UUID from the NIP-33 d-tag.
    let channel_id_str = extract_h_tag(event)
        .ok_or_else(|| IngestError::Rejected("invalid: missing h tag (channel_id)".into()))?;
    let channel_id = Uuid::parse_str(&channel_id_str)
        .map_err(|_| IngestError::Rejected("invalid: bad channel_id format".into()))?;

    let workflow_id_str = extract_d_tag(event)
        .ok_or_else(|| IngestError::Rejected("invalid: missing d tag (workflow_id)".into()))?;
    let workflow_id = Uuid::parse_str(&workflow_id_str)
        .map_err(|_| IngestError::Rejected("invalid: bad workflow_id format".into()))?;

    // 2. Validate caller has channel access (minimum: is a member)
    let is_member = state
        .is_member_cached(tenant.community(), channel_id, &self_bytes)
        .await
        .map_err(|e| IngestError::Internal(format!("error: membership check: {e}")))?;
    if !is_member {
        return Err(IngestError::Rejected(
            "forbidden: not a member of this channel".into(),
        ));
    }

    // 3. Parse YAML from event.content
    let (def, definition_json_str) = buzz_workflow::WorkflowEngine::parse_yaml(&event.content)
        .map_err(|e| IngestError::Rejected(format!("invalid: workflow YAML parse error: {e}")))?;
    let workflow_name = extract_tag(event, "name").unwrap_or_else(|| def.name.clone());

    let mut definition_json: serde_json::Value = serde_json::from_str(&definition_json_str)
        .map_err(|e| IngestError::Internal(format!("error: json parse of definition: {e}")))?;

    let existing_workflow = match state.db.get_workflow(tenant.community(), workflow_id).await {
        Ok(workflow) => {
            if workflow.owner_pubkey != self_bytes || workflow.channel_id != Some(channel_id) {
                return Err(IngestError::Rejected(
                    "forbidden: workflow belongs to a different owner or channel".into(),
                ));
            }
            Some(workflow)
        }
        Err(DbError::NotFound(_)) => None,
        Err(e) => {
            return Err(IngestError::Internal(format!(
                "error: db get_workflow: {e}"
            )));
        }
    };

    // Preserve the existing webhook secret across updates. A new secret is
    // returned only when the workflow first gains a webhook trigger.
    let webhook_secret = if matches!(def.trigger, buzz_workflow::TriggerDef::Webhook) {
        let existing_secret = existing_workflow
            .as_ref()
            .and_then(|workflow| webhook_secret::extract_secret(&workflow.definition));
        let secret = existing_secret.unwrap_or_else(webhook_secret::generate_webhook_secret);
        webhook_secret::inject_secret(&mut definition_json, &secret);
        if existing_workflow
            .as_ref()
            .and_then(|workflow| webhook_secret::extract_secret(&workflow.definition))
            .is_none()
        {
            Some(secret)
        } else {
            None
        }
    } else {
        None
    };

    // Compute hash AFTER secret injection
    let definition_json_final = serde_json::to_string(&definition_json)
        .map_err(|e| IngestError::Internal(format!("error: json serialize: {e}")))?;
    let hash = compute_definition_hash(&definition_json_final);

    // Persist the command event — returns open transaction
    let tx = match persist_command_event(state, tenant, event, None).await? {
        PersistResult::Duplicate => {
            return Ok(IngestResult {
                event_id: event.id.to_hex(),
                accepted: true,
                message: "duplicate: already processed".into(),
            });
        }
        PersistResult::Inserted(tx) => tx,
    };

    // 4. Execute: upsert by the NIP-33 d-tag UUID. A retry updates the same
    // row instead of creating another enabled workflow that would fan out on
    // every matching event. The workflow's community is the request's
    // server-bound tenant — never re-derived from the (client-supplied) channel
    // id. `community_of_channel(channel_id)` is ambiguous when the same channel
    // UUID exists in two communities and could mint the workflow under the wrong
    // tenant; `tenant.community()` is the authoritative owner. We then verify the
    // channel actually exists *inside that community* (scoped `get_channel`),
    // which fails closed if the client named a channel that belongs to a
    // different community — the same guarantee the `(community_id, channel_id)`
    // composite FK enforces on insert, surfaced here as a clean rejection.
    let community_id = tenant.community();
    state
        .db
        .get_channel(community_id, channel_id)
        .await
        .map_err(|_| IngestError::Rejected("invalid: workflow channel not found".into()))?;

    state
        .db
        .upsert_workflow(
            community_id,
            workflow_id,
            Some(channel_id),
            &self_bytes,
            &workflow_name,
            &definition_json_final,
            &hash,
        )
        .await
        .map_err(|e| match e {
            DbError::AccessDenied(_) => IngestError::Rejected(
                "forbidden: workflow belongs to a different owner or channel".into(),
            ),
            other => IngestError::Internal(format!("error: db upsert_workflow: {other}")),
        })?;

    // Drop the trigger-path cache entry so the new/updated definition fires on
    // the next matching event instead of after the cache TTL.
    state
        .workflow_engine
        .invalidate_channel_workflows(community_id, channel_id);

    // Commit the event transaction after the idempotent workflow upsert succeeds.
    tx.commit()
        .await
        .map_err(|e| IngestError::Internal(format!("error: commit transaction: {e}")))?;

    // 5. Return response
    let mut resp = serde_json::json!({
        "workflow_id": workflow_id.to_string(),
    });
    if let Some(secret) = webhook_secret {
        resp["webhook_secret"] = serde_json::Value::String(secret);
    }

    Ok(IngestResult {
        event_id: event.id.to_hex(),
        accepted: true,
        message: format!("response:{}", resp),
    })
}

async fn handle_workflow_trigger(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    auth: &IngestAuth,
) -> Result<IngestResult, IngestError> {
    let self_bytes = auth.pubkey().to_bytes().to_vec();

    // 1. Extract workflow reference from `d` tag or `e` tag
    let workflow_id_str = extract_d_tag(event)
        .or_else(|| extract_e_tag(event))
        .ok_or_else(|| {
            IngestError::Rejected("invalid: missing workflow reference (d or e tag)".into())
        })?;
    let workflow_id = Uuid::parse_str(&workflow_id_str)
        .map_err(|_| IngestError::Rejected("invalid: bad workflow_id format".into()))?;

    // 2. Validate workflow exists — scoped to the caller's community. The same
    // workflow UUID can exist in another community; a bare-id lookup could load
    // B's workflow and then satisfy the membership check below against B's
    // colliding channel, letting B trigger A's workflow.
    let community_id = tenant.community();
    let workflow = state
        .db
        .get_workflow(community_id, workflow_id)
        .await
        .map_err(|_| IngestError::Rejected("invalid: workflow not found".into()))?;

    // 3. Manual triggers execute with the workflow owner's authority, so only
    // the owner may start them. Channel membership alone is insufficient: a
    // member could otherwise invoke another user's webhook or message actions.
    if workflow.owner_pubkey != self_bytes {
        return Err(IngestError::Rejected(
            "forbidden: not authorized to trigger this workflow".into(),
        ));
    }

    // Persist the command event under the workflow channel even though the
    // trigger event itself only carries the workflow UUID. Storing channel
    // triggers as global events leaks workflow IDs to unrelated relay members.
    let tx = match persist_command_event(state, tenant, event, workflow.channel_id).await? {
        PersistResult::Duplicate => {
            return Ok(IngestResult {
                event_id: event.id.to_hex(),
                accepted: true,
                message: "duplicate: already processed".into(),
            });
        }
        PersistResult::Inserted(tx) => tx,
    };

    // 4. Execute: create workflow run
    let mut trigger_ctx = TriggerContext {
        channel_id: workflow
            .channel_id
            .map(|id| id.to_string())
            .unwrap_or_default(),
        author: hex::encode(&self_bytes),
        ..Default::default()
    };
    if !event.content.is_empty() {
        if let Ok(serde_json::Value::Object(map)) = serde_json::from_str(&event.content) {
            for (k, v) in map {
                let val_str = match v {
                    serde_json::Value::String(s) => s,
                    other => other.to_string(),
                };
                trigger_ctx.webhook_fields.insert(k, val_str);
            }
        }
    }
    let trigger_ctx_json = serde_json::to_value(&trigger_ctx).ok();

    let event_id_bytes = event.id.as_bytes().to_vec();
    let run_id = state
        .db
        .create_workflow_run(
            community_id,
            workflow_id,
            Some(&event_id_bytes),
            trigger_ctx_json.as_ref(),
        )
        .await
        .map_err(|e| IngestError::Internal(format!("error: db create_workflow_run: {e}")))?;

    // Commit: event + run creation succeeded atomically.
    tx.commit()
        .await
        .map_err(|e| IngestError::Internal(format!("error: commit transaction: {e}")))?;

    // 5. Spawn workflow execution
    let engine = Arc::clone(&state.workflow_engine);
    let db = state.db.clone();
    let def_value = workflow.definition.clone();
    let trigger_ctx_clone = trigger_ctx.clone();
    tokio::spawn(async move {
        let def: buzz_workflow::WorkflowDef = match serde_json::from_value(def_value) {
            Ok(d) => d,
            Err(e) => {
                tracing::error!("workflow_trigger: failed to parse definition: {e}");
                if let Err(db_err) = db
                    .update_workflow_run(
                        community_id,
                        run_id,
                        RunStatus::Failed,
                        0,
                        &serde_json::json!([]),
                        Some(&format!("definition parse error: {e}")),
                    )
                    .await
                {
                    tracing::error!("workflow_trigger: failed to mark run as failed: {db_err}");
                }
                return;
            }
        };

        let result = buzz_workflow::executor::execute_from_step(
            &engine,
            community_id,
            run_id,
            &def,
            &trigger_ctx_clone,
            0,
            None,
        )
        .await;
        engine
            .finalize_run(community_id, run_id, result, None)
            .await;
    });

    // 6. Return response
    Ok(IngestResult {
        event_id: event.id.to_hex(),
        accepted: true,
        message: format!(
            "response:{}",
            serde_json::json!({
                "run_id": run_id.to_string(),
            })
        ),
    })
}

/// Enforce the approver_spec field against the requesting pubkey.
///
/// Accepted specs:
/// - `""` or `"any"` — any authenticated user may approve.
/// - 64-char lowercase hex string — only that exact pubkey may approve.
///
/// All other formats are rejected (fail-closed).
fn check_approver_spec(approver_spec: &str, requester_hex: &str) -> Result<(), IngestError> {
    let spec = approver_spec.trim();

    // Empty or "any" — anyone may approve
    if spec.is_empty() || spec == "any" {
        return Ok(());
    }

    // Exact pubkey match (64-char hex, case-insensitive)
    if spec.len() == 64 && spec.chars().all(|c| c.is_ascii_hexdigit()) {
        if requester_hex.to_lowercase() == spec.to_lowercase() {
            return Ok(());
        }
        return Err(IngestError::Rejected(
            "forbidden: not the designated approver for this request".into(),
        ));
    }

    // Role-based or unrecognised — fail closed
    Err(IngestError::Rejected(format!(
        "forbidden: approver spec '{}' is not yet supported",
        spec
    )))
}

async fn handle_approval_grant(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    auth: &IngestAuth,
) -> Result<IngestResult, IngestError> {
    handle_terminal_approval(tenant, state, event, auth, ApprovalStatus::Granted).await
}

async fn handle_approval_deny(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    auth: &IngestAuth,
) -> Result<IngestResult, IngestError> {
    handle_terminal_approval(tenant, state, event, auth, ApprovalStatus::Denied).await
}

fn approval_note(event: &Event) -> Option<&str> {
    (!event.content.trim().is_empty()).then_some(event.content.as_str())
}

fn approval_request_event_id(approval: &ApprovalRecord) -> Result<String, IngestError> {
    let request_id = approval.request_event_id.as_deref().ok_or_else(|| {
        IngestError::Rejected("invalid: approval has no actionable request event".into())
    })?;
    if request_id.len() != 32 {
        return Err(IngestError::Rejected(
            "invalid: approval request event id is malformed".into(),
        ));
    }
    Ok(hex::encode(request_id))
}

fn build_approval_lifecycle_event(
    relay_keys: &nostr::Keys,
    kind: u32,
    token_hash_hex: &str,
    approval: &ApprovalRecord,
    actor_hex: &str,
    channel_id: Option<Uuid>,
    target_hex: Option<&str>,
) -> Result<Event, IngestError> {
    if !matches!(
        kind,
        KIND_WORKFLOW_APPROVAL_GRANTED
            | KIND_WORKFLOW_APPROVAL_DENIED
            | KIND_WORKFLOW_APPROVAL_DELEGATED
    ) {
        return Err(IngestError::Internal(format!(
            "error: unsupported approval lifecycle kind {kind}"
        )));
    }
    let request_id = approval_request_event_id(approval)?;
    let mut tags = vec![
        Tag::parse(["d", token_hash_hex])
            .map_err(|e| IngestError::Internal(format!("error: build lifecycle d tag: {e}")))?,
        Tag::parse(["e", &request_id])
            .map_err(|e| IngestError::Internal(format!("error: build lifecycle e tag: {e}")))?,
        Tag::parse(["workflow", &approval.workflow_id.to_string()]).map_err(|e| {
            IngestError::Internal(format!("error: build lifecycle workflow tag: {e}"))
        })?,
        Tag::parse(["run", &approval.run_id.to_string()])
            .map_err(|e| IngestError::Internal(format!("error: build lifecycle run tag: {e}")))?,
        Tag::parse(["step", &approval.step_id])
            .map_err(|e| IngestError::Internal(format!("error: build lifecycle step tag: {e}")))?,
        Tag::parse(["actor", actor_hex])
            .map_err(|e| IngestError::Internal(format!("error: build lifecycle actor tag: {e}")))?,
    ];
    if approval.approver_spec.len() == 64
        && approval
            .approver_spec
            .chars()
            .all(|character| character.is_ascii_hexdigit())
    {
        tags.push(Tag::parse(["p", &approval.approver_spec]).map_err(|e| {
            IngestError::Internal(format!("error: build lifecycle approver tag: {e}"))
        })?);
    }
    if let Some(channel_id) = channel_id {
        tags.push(
            Tag::parse(["h", &channel_id.to_string()])
                .map_err(|e| IngestError::Internal(format!("error: build lifecycle h tag: {e}")))?,
        );
    }
    if let Some(target_hex) = target_hex {
        tags.push(Tag::parse(["target", target_hex]).map_err(|e| {
            IngestError::Internal(format!("error: build lifecycle target tag: {e}"))
        })?);
    }
    EventBuilder::new(Kind::Custom(kind as u16), "")
        .tags(tags)
        .sign_with_keys(relay_keys)
        .map_err(|e| IngestError::Internal(format!("error: sign approval lifecycle: {e}")))
}

async fn load_pending_approval(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    actor_hex: &str,
) -> Result<(Vec<u8>, String, ApprovalRecord), IngestError> {
    let token_hash_hex = extract_d_tag(event)
        .ok_or_else(|| IngestError::Rejected("invalid: missing approval digest d tag".into()))?;
    if token_hash_hex.len() != 64
        || !token_hash_hex
            .chars()
            .all(|character| character.is_ascii_hexdigit())
    {
        return Err(IngestError::Rejected(
            "invalid: approval digest must be 64 hexadecimal characters".into(),
        ));
    }
    let token_hash = hex::decode(&token_hash_hex)
        .map_err(|_| IngestError::Rejected("invalid: bad approval token hash hex".into()))?;
    let approval = state
        .db
        .get_approval_by_stored_hash(tenant.community(), &token_hash)
        .await
        .map_err(|_| IngestError::Rejected("invalid: approval not found".into()))?;
    if approval.status != ApprovalStatus::Pending {
        return Err(IngestError::Rejected(format!(
            "invalid: approval already {}",
            approval.status
        )));
    }
    if Utc::now() > approval.expires_at {
        return Err(IngestError::Rejected(
            "invalid: approval token has expired".into(),
        ));
    }
    check_approver_spec(&approval.approver_spec, actor_hex)?;
    Ok((token_hash, token_hash_hex, approval))
}

async fn handle_terminal_approval(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    auth: &IngestAuth,
    status: ApprovalStatus,
) -> Result<IngestResult, IngestError> {
    if state
        .db
        .get_event_by_id(tenant.community(), event.id.as_bytes())
        .await
        .map_err(|error| {
            IngestError::Internal(format!("error: check duplicate approval command: {error}"))
        })?
        .is_some()
    {
        return Ok(IngestResult {
            event_id: event.id.to_hex(),
            accepted: true,
            message: "duplicate: already processed".into(),
        });
    }
    let actor_bytes = auth.pubkey().to_bytes().to_vec();
    let actor_hex = auth.pubkey().to_hex();
    let (token_hash, token_hash_hex, approval) =
        load_pending_approval(tenant, state, event, &actor_hex).await?;
    let lifecycle_kind = match status {
        ApprovalStatus::Granted => KIND_WORKFLOW_APPROVAL_GRANTED,
        ApprovalStatus::Denied => KIND_WORKFLOW_APPROVAL_DENIED,
        _ => {
            return Err(IngestError::Internal(
                "error: terminal approval handler received unsupported status".into(),
            ));
        }
    };
    let request_id = approval_request_event_id(&approval)?;
    let request_event = state
        .db
        .get_event_by_id(
            tenant.community(),
            &hex::decode(&request_id).map_err(|_| {
                IngestError::Rejected("invalid: malformed approval request event id".into())
            })?,
        )
        .await
        .map_err(|e| IngestError::Internal(format!("error: load approval request: {e}")))?
        .ok_or_else(|| IngestError::Rejected("invalid: approval request event not found".into()))?;
    let channel_id = request_event.channel_id;
    let lifecycle = build_approval_lifecycle_event(
        &state.relay_keypair,
        lifecycle_kind,
        &token_hash_hex,
        &approval,
        &actor_hex,
        channel_id,
        None,
    )?;
    let decision = match status {
        ApprovalStatus::Granted => ApprovalDecision::Grant {
            actor: &actor_bytes,
            note: approval_note(event),
        },
        ApprovalStatus::Denied => ApprovalDecision::Deny {
            actor: &actor_bytes,
            note: approval_note(event),
        },
        _ => unreachable!("status validated above"),
    };
    let outcome = state
        .db
        .apply_approval_decision(ApprovalDecisionParams {
            community_id: tenant.community(),
            token_hash: &token_hash,
            decision,
            command_event: event,
            lifecycle_event: &lifecycle,
            delegated_task_event: None,
            channel_id,
        })
        .await
        .map_err(|error| match error {
            DbError::InvalidData(message) | DbError::NotFound(message) => {
                IngestError::Rejected(format!("invalid: {message}"))
            }
            other => IngestError::Internal(format!("error: apply approval decision: {other}")),
        })?;

    let applied = match outcome {
        ApprovalDecisionOutcome::Duplicate => {
            return Ok(IngestResult {
                event_id: event.id.to_hex(),
                accepted: true,
                message: "duplicate: already processed".into(),
            });
        }
        ApprovalDecisionOutcome::Applied(applied) => applied,
    };
    let relay_hex = state.relay_keypair.public_key().to_hex();
    dispatch_persistent_event(
        tenant,
        state,
        &applied.lifecycle_event,
        lifecycle_kind,
        &relay_hex,
        None,
    )
    .await;

    if status == ApprovalStatus::Granted {
        let community_id = tenant.community();
        let run_id = approval.run_id;
        let workflow_id = approval.workflow_id;
        let resume_index = usize::try_from(approval.step_index)
            .map_err(|_| IngestError::Internal("error: negative approval step index".into()))?
            + 1;
        let engine = Arc::clone(&state.workflow_engine);
        let db = state.db.clone();
        tokio::spawn(async move {
            resume_workflow_after_approval(
                engine,
                db,
                community_id,
                run_id,
                workflow_id,
                resume_index,
            )
            .await;
        });
    }

    Ok(IngestResult {
        event_id: event.id.to_hex(),
        accepted: true,
        message: format!(
            "response:{}",
            serde_json::json!({
                "status": status.to_string(),
                "run_id": approval.run_id.to_string(),
            })
        ),
    })
}

fn requester_agent_pubkey(request_event: &Event) -> Option<Vec<u8>> {
    request_event.tags.iter().find_map(|tag| {
        let values = tag.as_slice();
        if values.first().map(String::as_str) != Some("agent") {
            return None;
        }
        values
            .get(1)
            .and_then(|value| nostr::PublicKey::from_hex(value).ok())
            .map(|pubkey| pubkey.to_bytes().to_vec())
    })
}

fn build_delegated_task_event(
    relay_keys: &nostr::Keys,
    approval: &ApprovalRecord,
    request_event: &Event,
    channel_id: Uuid,
    target_hex: &str,
    actor_hex: &str,
    note: Option<&str>,
) -> Result<Event, IngestError> {
    let request_id = request_event.id.to_hex();
    let content = match note.filter(|note| !note.trim().is_empty()) {
        Some(note) => format!("{}\n\nPass note: {}", request_event.content, note.trim()),
        None => request_event.content.clone(),
    };
    let tags = vec![
        Tag::parse(["h", &channel_id.to_string()])
            .map_err(|e| IngestError::Internal(format!("error: build task h tag: {e}")))?,
        Tag::parse(["e", &request_id, "", "reply"])
            .map_err(|e| IngestError::Internal(format!("error: build task e tag: {e}")))?,
        Tag::parse(["p", target_hex])
            .map_err(|e| IngestError::Internal(format!("error: build task p tag: {e}")))?,
        Tag::parse(["workflow", &approval.workflow_id.to_string()])
            .map_err(|e| IngestError::Internal(format!("error: build task workflow tag: {e}")))?,
        Tag::parse(["run", &approval.run_id.to_string()])
            .map_err(|e| IngestError::Internal(format!("error: build task run tag: {e}")))?,
        Tag::parse(["step", &approval.step_id])
            .map_err(|e| IngestError::Internal(format!("error: build task step tag: {e}")))?,
        Tag::parse(["actor", actor_hex])
            .map_err(|e| IngestError::Internal(format!("error: build task actor tag: {e}")))?,
    ];
    EventBuilder::new(Kind::Custom(KIND_STREAM_MESSAGE as u16), content)
        .tags(tags)
        .sign_with_keys(relay_keys)
        .map_err(|e| IngestError::Internal(format!("error: sign delegated task: {e}")))
}

async fn handle_approval_pass(
    tenant: &TenantContext,
    state: &Arc<AppState>,
    event: &Event,
    auth: &IngestAuth,
) -> Result<IngestResult, IngestError> {
    if state
        .db
        .get_event_by_id(tenant.community(), event.id.as_bytes())
        .await
        .map_err(|error| {
            IngestError::Internal(format!("error: check duplicate approval pass: {error}"))
        })?
        .is_some()
    {
        return Ok(IngestResult {
            event_id: event.id.to_hex(),
            accepted: true,
            message: "duplicate: already processed".into(),
        });
    }
    let actor_bytes = auth.pubkey().to_bytes().to_vec();
    let actor_hex = auth.pubkey().to_hex();
    let target_bytes = extract_pass_target(event)?;
    let target = nostr::PublicKey::from_slice(&target_bytes)
        .map_err(|_| IngestError::Rejected("invalid: malformed target agent pubkey".into()))?;
    let target_hex = target.to_hex();
    let (token_hash, token_hash_hex, approval) =
        load_pending_approval(tenant, state, event, &actor_hex).await?;
    let request_id = approval_request_event_id(&approval)?;
    if extract_e_tag(event).as_deref() != Some(request_id.as_str()) {
        return Err(IngestError::Rejected(
            "invalid: approval pass e tag does not match its request".into(),
        ));
    }
    let request_event = state
        .db
        .get_event_by_id(
            tenant.community(),
            &hex::decode(&request_id).map_err(|_| {
                IngestError::Rejected("invalid: malformed approval request event id".into())
            })?,
        )
        .await
        .map_err(|e| IngestError::Internal(format!("error: load approval request: {e}")))?
        .ok_or_else(|| IngestError::Rejected("invalid: approval request event not found".into()))?;
    let channel_id = request_event.channel_id.ok_or_else(|| {
        IngestError::Rejected("invalid: only channel-scoped approvals can be passed".into())
    })?;
    if extract_h_tag(event).as_deref() != Some(channel_id.to_string().as_str()) {
        return Err(IngestError::Rejected(
            "invalid: approval pass h tag does not match its request channel".into(),
        ));
    }

    let is_member = state
        .is_member_cached(tenant.community(), channel_id, &target_bytes)
        .await
        .map_err(|e| IngestError::Internal(format!("error: check target membership: {e}")))?;
    let (invocation_policy, agent_owner) = state
        .db
        .get_agent_channel_policy(tenant.community(), &target_bytes)
        .await
        .map_err(|e| IngestError::Internal(format!("error: load target agent policy: {e}")))?
        .ok_or_else(|| IngestError::Rejected("invalid: pass target does not exist".into()))?;
    let presence = state
        .pubsub
        .get_presence(tenant, &target)
        .await
        .map_err(|e| IngestError::Internal(format!("error: load target agent presence: {e}")))?;
    let requester = requester_agent_pubkey(&request_event.event);
    validate_pass_target_policy(
        &actor_bytes,
        requester.as_deref(),
        &target_bytes,
        is_member,
        agent_owner.as_deref(),
        &invocation_policy,
        presence.as_deref(),
    )?;

    let lifecycle = build_approval_lifecycle_event(
        &state.relay_keypair,
        KIND_WORKFLOW_APPROVAL_DELEGATED,
        &token_hash_hex,
        &approval,
        &actor_hex,
        Some(channel_id),
        Some(&target_hex),
    )?;
    let task = build_delegated_task_event(
        &state.relay_keypair,
        &approval,
        &request_event.event,
        channel_id,
        &target_hex,
        &actor_hex,
        approval_note(event),
    )?;
    let outcome = state
        .db
        .apply_approval_decision(ApprovalDecisionParams {
            community_id: tenant.community(),
            token_hash: &token_hash,
            decision: ApprovalDecision::Pass {
                actor: &actor_bytes,
                target: &target_bytes,
                note: approval_note(event),
            },
            command_event: event,
            lifecycle_event: &lifecycle,
            delegated_task_event: Some(&task),
            channel_id: Some(channel_id),
        })
        .await
        .map_err(|error| match error {
            DbError::InvalidData(message) | DbError::NotFound(message) => {
                IngestError::Rejected(format!("invalid: {message}"))
            }
            other => IngestError::Internal(format!("error: apply approval pass: {other}")),
        })?;
    let applied = match outcome {
        ApprovalDecisionOutcome::Duplicate => {
            return Ok(IngestResult {
                event_id: event.id.to_hex(),
                accepted: true,
                message: "duplicate: already processed".into(),
            });
        }
        ApprovalDecisionOutcome::Applied(applied) => applied,
    };

    let relay_hex = state.relay_keypair.public_key().to_hex();
    if let Some(task) = applied.delegated_task_event.as_ref() {
        dispatch_persistent_event(tenant, state, task, KIND_STREAM_MESSAGE, &relay_hex, None).await;
    }
    dispatch_persistent_event(
        tenant,
        state,
        &applied.lifecycle_event,
        KIND_WORKFLOW_APPROVAL_DELEGATED,
        &relay_hex,
        None,
    )
    .await;

    Ok(IngestResult {
        event_id: event.id.to_hex(),
        accepted: true,
        message: format!(
            "response:{}",
            serde_json::json!({
                "status": "delegated",
                "run_id": approval.run_id.to_string(),
                "target": target_hex,
                "task_event_id": applied
                    .delegated_task_event
                    .as_ref()
                    .map(|task| task.event.id.to_hex()),
            })
        ),
    })
}

/// Resume a suspended workflow run after an approval gate has been granted.
async fn resume_workflow_after_approval(
    engine: Arc<buzz_workflow::WorkflowEngine>,
    db: buzz_db::Db,
    community_id: CommunityId,
    run_id: Uuid,
    workflow_id: Uuid,
    resume_index: usize,
) {
    let run = match db.get_workflow_run(community_id, run_id).await {
        Ok(r) => r,
        Err(e) => {
            tracing::error!("resume_workflow: failed to fetch run {run_id}: {e}");
            return;
        }
    };

    // Guard: only resume runs that are actually waiting for approval
    if run.status != RunStatus::WaitingApproval {
        tracing::warn!(
            "resume_workflow: run {run_id} has status '{}', expected 'waiting_approval'",
            run.status
        );
        return;
    }

    let workflow = match db.get_workflow(community_id, workflow_id).await {
        Ok(w) => w,
        Err(e) => {
            tracing::error!("resume_workflow: failed to fetch workflow {workflow_id}: {e}");
            return;
        }
    };

    let def: buzz_workflow::WorkflowDef = match serde_json::from_value(workflow.definition.clone())
    {
        Ok(d) => d,
        Err(e) => {
            tracing::error!("resume_workflow: failed to parse workflow definition: {e}");
            if let Err(db_err) = db
                .update_workflow_run(
                    community_id,
                    run_id,
                    RunStatus::Failed,
                    run.current_step,
                    &run.execution_trace,
                    Some(&format!("definition parse error: {e}")),
                )
                .await
            {
                tracing::error!("resume_workflow: failed to mark run as failed: {db_err}");
            }
            return;
        }
    };

    // Reconstruct step_outputs from execution trace for template resolution
    let mut initial_outputs: std::collections::HashMap<String, serde_json::Value> =
        std::collections::HashMap::new();
    if let Some(trace_arr) = run.execution_trace.as_array() {
        for entry in trace_arr {
            if let (Some(step_id), Some(output)) = (
                entry.get("step_id").and_then(|v| v.as_str()),
                entry.get("output"),
            ) {
                initial_outputs.insert(step_id.to_string(), output.clone());
            }
        }
    }

    // Restore trigger context for {{trigger.*}} templates
    let trigger_ctx: TriggerContext = run
        .trigger_context
        .as_ref()
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();

    // Execute remaining steps
    let existing_trace = run.execution_trace.as_array().cloned();
    let result = buzz_workflow::executor::execute_from_step(
        &engine,
        community_id,
        run_id,
        &def,
        &trigger_ctx,
        resume_index,
        Some(initial_outputs),
    )
    .await;
    engine
        .finalize_run(community_id, run_id, result, existing_trace)
        .await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use nostr::{EventBuilder, Kind, Tag};

    fn signed_pass_event(targets: &[&str]) -> Event {
        let mut tags = vec![Tag::parse(["d", &"ab".repeat(32)]).expect("d tag")];
        for target in targets {
            tags.push(Tag::parse(["p", *target]).expect("p tag"));
        }
        EventBuilder::new(Kind::Custom(KIND_APPROVAL_PASS as u16), "")
            .tags(tags)
            .sign_with_keys(&nostr::Keys::generate())
            .expect("sign pass")
    }

    fn approval_record(request_id: &nostr::EventId) -> ApprovalRecord {
        ApprovalRecord {
            token: vec![0xab; 32],
            workflow_id: Uuid::from_u128(2),
            run_id: Uuid::from_u128(3),
            step_id: "gate".to_owned(),
            step_index: 4,
            approver_spec: "11".repeat(32),
            status: ApprovalStatus::Pending,
            approver_pubkey: None,
            delegated_to_pubkey: None,
            delegated_at: None,
            request_event_id: Some(request_id.as_bytes().to_vec()),
            note: None,
            expires_at: Utc::now() + chrono::Duration::hours(1),
            created_at: Utc::now(),
        }
    }

    fn tag_values(event: &Event, name: &str) -> Vec<String> {
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
    fn pass_requires_exactly_one_valid_target_pubkey() {
        let first = "11".repeat(32);
        let second = "22".repeat(32);

        assert_eq!(
            extract_pass_target(&signed_pass_event(&[&first])).expect("one target"),
            hex::decode(&first).expect("target bytes")
        );
        assert!(extract_pass_target(&signed_pass_event(&[])).is_err());
        assert!(extract_pass_target(&signed_pass_event(&[&first, &second])).is_err());
        assert!(extract_pass_target(&signed_pass_event(&["not-a-pubkey"])).is_err());
    }

    #[test]
    fn pass_target_must_be_distinct_registered_invocable_present_member() {
        let actor = [1_u8; 32];
        let requester = [2_u8; 32];
        let target = [3_u8; 32];

        assert!(validate_pass_target_policy(
            &actor,
            Some(&requester),
            &target,
            true,
            Some(&actor),
            "owner_only",
            Some("online"),
        )
        .is_ok());
        assert!(validate_pass_target_policy(
            &actor,
            Some(&requester),
            &target,
            true,
            Some(&requester),
            "anyone",
            Some("away"),
        )
        .is_ok());

        for rejected in [
            validate_pass_target_policy(
                &actor,
                Some(&requester),
                &actor,
                true,
                Some(&actor),
                "anyone",
                Some("online"),
            ),
            validate_pass_target_policy(
                &actor,
                Some(&requester),
                &requester,
                true,
                Some(&actor),
                "anyone",
                Some("online"),
            ),
            validate_pass_target_policy(
                &actor,
                Some(&requester),
                &target,
                false,
                Some(&actor),
                "anyone",
                Some("online"),
            ),
            validate_pass_target_policy(
                &actor,
                Some(&requester),
                &target,
                true,
                None,
                "anyone",
                Some("online"),
            ),
            validate_pass_target_policy(
                &actor,
                Some(&requester),
                &target,
                true,
                Some(&requester),
                "owner_only",
                Some("online"),
            ),
            validate_pass_target_policy(
                &actor,
                Some(&requester),
                &target,
                true,
                Some(&actor),
                "nobody",
                Some("online"),
            ),
            validate_pass_target_policy(
                &actor,
                Some(&requester),
                &target,
                true,
                Some(&actor),
                "anyone",
                None,
            ),
            validate_pass_target_policy(
                &actor,
                Some(&requester),
                &target,
                true,
                Some(&actor),
                "anyone",
                Some("offline"),
            ),
        ] {
            assert!(rejected.is_err());
        }
    }

    #[test]
    fn delegated_lifecycle_and_task_bind_the_original_request() {
        let relay = nostr::Keys::generate();
        let request = EventBuilder::new(
            Kind::Custom(KIND_WORKFLOW_APPROVAL_REQUESTED as u16),
            "Ship it?",
        )
        .sign_with_keys(&relay)
        .expect("sign request");
        let approval = approval_record(&request.id);
        let digest = "ab".repeat(32);
        let actor = "11".repeat(32);
        let target = "22".repeat(32);
        let channel = Uuid::from_u128(5);

        let lifecycle = build_approval_lifecycle_event(
            &relay,
            KIND_WORKFLOW_APPROVAL_DELEGATED,
            &digest,
            &approval,
            &actor,
            Some(channel),
            Some(&target),
        )
        .expect("delegated lifecycle");
        let task = build_delegated_task_event(
            &relay,
            &approval,
            &request,
            channel,
            &target,
            &actor,
            Some("Please investigate"),
        )
        .expect("delegated task");

        assert_eq!(lifecycle.kind.as_u16(), 46_013);
        assert_eq!(tag_values(&lifecycle, "d"), vec![digest]);
        assert_eq!(tag_values(&lifecycle, "e"), vec![request.id.to_hex()]);
        assert_eq!(tag_values(&lifecycle, "actor"), vec![actor.clone()]);
        assert_eq!(tag_values(&lifecycle, "target"), vec![target.clone()]);
        assert_eq!(tag_values(&lifecycle, "p"), vec!["11".repeat(32)]);
        assert_eq!(tag_values(&lifecycle, "h"), vec![channel.to_string()]);
        assert_eq!(task.kind.as_u16(), 9);
        assert_eq!(tag_values(&task, "p"), vec![target]);
        assert_eq!(tag_values(&task, "h"), vec![channel.to_string()]);
        assert_eq!(tag_values(&task, "e"), vec![request.id.to_hex()]);
        assert_eq!(task.content, "Ship it?\n\nPass note: Please investigate");
    }
}
