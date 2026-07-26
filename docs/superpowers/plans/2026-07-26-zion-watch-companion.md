# Zion Watch Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a minimal Apple Watch companion for Zion that presents a focused queue of approval requests, direct messages, and mentions, and lets the wearer approve, deny, pass, or open an item on the paired iPhone.

**Architecture:** The watch remains a dependent, credential-free SwiftUI companion. The authenticated Flutter iPhone app derives a bounded watch inbox from the active Zion community, transfers snapshots and action results through `WatchConnectivity`, owns APNs enrollment and NIP-PL leases, and signs all Nostr commands. The relay emits actionable approval lifecycle events, executes approve/deny/pass transactionally, and sends only compile-time generic APNs payloads selected by a closed wake-class enum.

**Tech Stack:** Rust, SQLx/PostgreSQL, Nostr, Axum, APNs HTTP/2, Flutter/Dart, Riverpod, Swift, SwiftUI, WatchConnectivity, UserNotifications, DeviceCheck App Attest, XCTest, Flutter widget/unit tests, and XcodeBuildMCP.

## Global Constraints

- Preserve the existing uncommitted files in the main checkout. Do all implementation work in an isolated `codex/zion-watch` worktree and stage only named paths.
- Keep the existing `BUZZ_*` compatibility surface, module/package names, relay URLs, Nostr routes, and desktop/mobile behavior unless a change is explicitly listed here.
- Use Nostr events rather than a new feature-specific HTTP API. The only HTTP work is the existing NIP-PL push-gateway enrollment/delivery surface.
- Add public Rust API documentation, introduce no production `unwrap()` or `expect()`, and add no `unsafe`.
- Keep the watch credential-free: no Nostr secret key, relay token, APNs endpoint grant, or raw notification content is persisted on watchOS.
- Scope the watch to the iPhone app's active community. A community switch or sign-out clears the watch snapshot, pending action ledger, and push lease before sending new state.
- Bound watch payloads to 20 items and 2,000 Unicode scalars per item. Approvals sort before direct messages and mentions; items within each class sort newest first.
- APNs alerts always say `Zion needs attention`. Approval wakes use the time-sensitive interruption level; message and mention wakes use the default class. No relay-supplied text reaches APNs.
- A Pass operation is one server transaction: consume the pending approval, mark the original run delegated/cancelled, insert the linked agent task reply, persist the delegated lifecycle event, and update thread counters. Any failure rolls back all mutations.
- Validate Pass targets server-side: same community and channel, different from requester and actor, invocable by the actor, registered as an agent, and currently online or away with an unexpired presence record.
- Follow mobile repository rules: Riverpod plus `HookConsumerWidget`/`ConsumerWidget`, no `StatefulWidget`, no cross-feature imports, `Grid`/`Radii` tokens, and no `flutter run`, `flutter build`, `flutter clean`, or `flutter upgrade`.
- Target watchOS 26.0 with the installed watchOS 26 SDK. Keep the iOS deployment target and signing team inherited from the existing Runner configuration.

---

## Task 1: Establish the Approval and Push Protocol Contract

**Files:**

- Modify: `crates/buzz-core/src/kind.rs`
- Modify: `crates/buzz-sdk/src/builders.rs`
- Modify: `crates/buzz-db/src/workflow.rs`
- Modify: `crates/buzz-db/src/push.rs`
- Modify: `crates/buzz-db/src/migration.rs`
- Create: `migrations/0025_zion_watch_approvals_push.sql`

- [ ] **Step 1: Add failing kind and builder tests**

Add unit tests that require:

```rust
assert!(is_command_kind(KIND_APPROVAL_PASS));
assert!(is_workflow_execution_kind(KIND_WORKFLOW_APPROVAL_DELEGATED));
assert_eq!(KIND_APPROVAL_PASS, 46032);
assert_eq!(KIND_WORKFLOW_APPROVAL_DELEGATED, 46013);
```

Add SDK tests for:

```rust
build_workflow_approval_pass(&token_hash, &target_pubkey, "Please take this")
```

The builder must emit kind `46032`, a `d` tag containing the 64-character token hash, a `p` tag containing the target agent pubkey, and the note as content. Reject malformed hashes, malformed pubkeys, and an empty target.

- [ ] **Step 2: Run the focused tests and confirm the red state**

Run:

```bash
. ./bin/activate-hermit
cargo test -p buzz-core kind
cargo test -p buzz-sdk workflow_approval
```

Expected: compilation fails because `KIND_APPROVAL_PASS`, `KIND_WORKFLOW_APPROVAL_DELEGATED`, and `build_workflow_approval_pass` do not exist.

- [ ] **Step 3: Add the protocol constants and builder**

Define:

```rust
pub const KIND_APPROVAL_PASS: u32 = 46032;
pub const KIND_WORKFLOW_APPROVAL_DELEGATED: u32 = 46013;
```

Extend the execution-kind range through `46013`, add Pass to `is_command_kind`, add both kinds to the public kind registry, and implement the validated SDK builder.

- [ ] **Step 4: Add failing migration and database-model tests**

Extend `ApprovalStatus` tests to require `Delegated` to display and parse as `delegated`. Add migration assertions requiring:

- `approval_status` gains `delegated`.
- `workflow_approvals` gains nullable `delegated_to_pubkey BYTEA`, `delegated_at TIMESTAMPTZ`, and `request_event_id BYTEA`.
- the push enqueue trigger allowlist is exactly `7, 9, 1059, 40002, 40007, 46010`.

Run:

```bash
. ./bin/activate-hermit
cargo test -p buzz-db approval_status
cargo test -p buzz-db migration
```

Expected: the delegated status and migration assertions fail.

- [ ] **Step 5: Write migration `0025_zion_watch_approvals_push.sql`**

Use an idempotent enum addition:

```sql
ALTER TYPE approval_status ADD VALUE IF NOT EXISTS 'delegated';
```

Add the three nullable approval columns, indexes for pending approver queries, and replace `enqueue_push_match_job()` so its allowlist contains `40002`. Keep the advisory-lock lost-wake protocol from migration `0023_push_match_gate.sql` byte-for-byte except for that allowlist.

- [ ] **Step 6: Extend the database types**

Add `ApprovalStatus::Delegated`, map the new fields in `ApprovalRecord`, and update `update_approval_by_stored_hash` so delegated transitions stamp `delegated_at` and store a validated 32-byte target pubkey. Keep the `status = 'pending'` conflict fence.

Update `backfill_push_match_jobs` to use the same six-kind allowlist as the relay descriptor and migration trigger.

- [ ] **Step 7: Run the focused green checks**

Run:

```bash
. ./bin/activate-hermit
cargo fmt --all -- --check
cargo test -p buzz-core kind
cargo test -p buzz-sdk workflow_approval
cargo test -p buzz-db approval_status
cargo test -p buzz-db migration
```

Expected: all pass.

- [ ] **Step 8: Commit the protocol contract**

```bash
git add crates/buzz-core/src/kind.rs crates/buzz-sdk/src/builders.rs \
  crates/buzz-db/src/workflow.rs crates/buzz-db/src/push.rs \
  crates/buzz-db/src/migration.rs migrations/0025_zion_watch_approvals_push.sql
git commit -m "feat: define Zion Watch approval protocol"
```

---

## Task 2: Emit Durable, Actionable Approval Requests

**Files:**

- Modify: `crates/buzz-workflow/src/action_sink.rs`
- Modify: `crates/buzz-workflow/src/executor.rs`
- Modify: `crates/buzz-workflow/src/lib.rs`
- Modify: `crates/buzz-relay/src/workflow_sink.rs`
- Modify: `crates/buzz-db/src/workflow.rs`
- Modify: `crates/buzz-db/src/event.rs`
- Modify: `crates/buzz-relay/src/handlers/command_executor.rs`

- [ ] **Step 1: Specify the relay-agnostic approval request**

Add a documented workflow type:

```rust
pub struct ApprovalRequest {
    pub community_id: CommunityId,
    pub workflow_id: Uuid,
    pub run_id: Uuid,
    pub step_id: String,
    pub step_index: i32,
    pub approver_spec: String,
    pub message: String,
    pub expires_at: DateTime<Utc>,
    pub channel_id: Option<Uuid>,
    pub owner_pubkey: String,
    pub execution_trace: JsonValue,
}
```

Extend `ActionSink` with:

```rust
fn request_approval(
    &self,
    request: ApprovalRequest,
) -> Pin<Box<dyn Future<Output = Result<ApprovalReceipt, ActionSinkError>> + Send + '_>>;
```

The sink generates and immediately hashes the random token, persists only the digest, and returns the public request event ID in `ApprovalReceipt`. The raw token never leaves the relay sink.

- [ ] **Step 2: Add failing executor and fake-sink tests**

Test that `RequestApproval` invokes the sink exactly once, passes the workflow/run/step/community context, and returns `StepResult::Suspended` with the durable request event ID. Test that a sink error fails the run instead of leaving an untracked suspension.

Run:

```bash
. ./bin/activate-hermit
cargo test -p buzz-workflow request_approval
```

Expected: compilation fails because the trait method and request type are missing.

- [ ] **Step 3: Implement the executor call**

Move random-token generation to the relay implementation. In the workflow engine, call `request_approval`, preserve the current trace/step outputs, set the run to `waiting_approval`, and remove the explicit “approval gates are not implemented” failure in `finalize_run`.

- [ ] **Step 4: Add failing relay-sink tests**

Add tests for exact approver resolution:

- A 64-character member pubkey resolves directly.
- `@display-name` resolves only when exactly one channel member matches.
- Missing, ambiguous, or non-member human approvers fail closed.
- The approval request event has kind `46010`, exact `h` and approver `p` tags, workflow/run/step tags, a `d` tag with the SHA-256 token digest, and no raw token.
- The workflow owner appears as an `agent` tag only when the user record has an agent owner pubkey.
- Event insertion, approval insertion, and run-state update occur in one SQL transaction.

Run:

```bash
. ./bin/activate-hermit
cargo test -p buzz-relay workflow_sink::tests::request_approval
```

Expected: tests fail because the relay sink does not implement the new trait method.

- [ ] **Step 5: Add transaction-aware database operations**

Expose a documented transaction form of event insertion that preserves event TTL, search indexing, thread metadata, and counters. Add:

```rust
pub async fn create_actionable_approval_tx(
    tx: &mut Transaction<'_, Postgres>,
    approval: &NewApproval,
    request_event: &EventRecord,
) -> Result<()>;
```

It must insert the relay-signed event, store only `SHA256(raw_token)`, set `request_event_id`, insert the approval row, and update the run to `waiting_approval` before commit.

- [ ] **Step 6: Implement relay-side request creation**

In `RelayActionSink::request_approval`:

1. Resolve the active community/channel.
2. Resolve and authorize the exact approver.
3. Generate a UUID token and SHA-256 digest.
4. Build and relay-sign kind `46010` with generic structured tags and the human prompt in the event content.
5. Call `create_actionable_approval_tx`.
6. Commit.
7. Dispatch the already-persisted event to live subscribers.
8. Discard the raw token and return the public request event ID to the workflow engine.

If signing, persistence, or dispatch preparation fails before commit, leave no approval or event. A post-commit live-dispatch failure is logged and recovered by normal relay replay.

- [ ] **Step 7: Run focused workflow and relay checks**

Run:

```bash
. ./bin/activate-hermit
cargo test -p buzz-workflow request_approval
cargo test -p buzz-relay workflow_sink
cargo test -p buzz-db workflow
```

Expected: all pass.

- [ ] **Step 8: Commit actionable approval emission**

```bash
git add crates/buzz-workflow/src/action_sink.rs crates/buzz-workflow/src/executor.rs \
  crates/buzz-workflow/src/lib.rs \
  crates/buzz-relay/src/workflow_sink.rs crates/buzz-db/src/workflow.rs \
  crates/buzz-db/src/event.rs crates/buzz-relay/src/handlers/command_executor.rs
git commit -m "feat: emit actionable workflow approvals"
```

---

## Task 3: Make Approve, Deny, and Pass Transactional

**Files:**

- Modify: `crates/buzz-relay/src/handlers/command_executor.rs`
- Modify: `crates/buzz-relay/src/handlers/ingest.rs`
- Modify: `crates/buzz-relay/src/handlers/event.rs`
- Modify: `crates/buzz-relay/src/state.rs`
- Modify: `crates/buzz-db/src/workflow.rs`
- Modify: `crates/buzz-db/src/event.rs`
- Modify: `crates/buzz-sdk/src/builders.rs`
- Modify: `desktop/src-tauri/src/commands/workflows.rs`

- [ ] **Step 1: Add red integration tests for decision atomicity**

Extend command-executor tests to prove:

- Grant atomically changes pending to granted, persists command `46030`, persists relay lifecycle `46011`, and resumes the run.
- Deny atomically changes pending to denied, persists command `46031`, persists lifecycle `46012`, and cancels the run.
- Concurrent decisions produce exactly one success and one conflict.
- A forced event-insert or run-update error leaves the approval pending and persists neither command nor lifecycle event.

Run:

```bash
. ./bin/activate-hermit
cargo test -p buzz-relay approval_
```

Expected: rollback and lifecycle assertions fail against the current pool-level mutation.

- [ ] **Step 2: Implement one decision transaction**

Create:

```rust
pub enum ApprovalDecision<'a> {
    Grant { actor: &'a [u8], note: Option<&'a str> },
    Deny { actor: &'a [u8], note: Option<&'a str> },
    Pass { actor: &'a [u8], target: &'a [u8], note: Option<&'a str> },
}
```

and a database method that locks the pending approval row, applies the decision, inserts the user command and relay lifecycle events through the transaction-aware event path, and updates the run. Grant leaves the run resumable; deny and pass set it cancelled with a reason.

- [ ] **Step 3: Add red Pass validation tests**

Add tests rejecting:

- missing or multiple `p` target tags;
- actor as target;
- original requester as target;
- target outside the channel/community;
- target without an agent registration;
- target the actor cannot invoke;
- offline, expired, or stale presence;
- a non-pending approval or a token hash from another community.

Add success tests requiring an online or away target, an unexpired presence timestamp, and exactly one linked task reply.

- [ ] **Step 4: Implement target validation before mutation**

Parse kind `46032`, bind `d` to the server-scoped approval, read the original kind `46010` requester/channel context, and validate the target through existing membership, agent policy, and presence services. Treat no presence or an expired presence as offline.

- [ ] **Step 5: Build the linked task and delegated lifecycle**

Before opening the transaction, build and relay-sign:

- a kind `9` channel reply containing the original approval prompt plus the optional Pass note;
- `h` channel scope;
- `e` reply/root references to the original approval request;
- `p` target agent mention;
- workflow/run/step correlation tags;
- lifecycle kind `46013` with the approval digest, actor, and target tags.

Inside the transaction insert command `46032`, update the approval to delegated, cancel the old run, insert the task reply and lifecycle event, and update reply/descendant counters. Dispatch both relay events after commit.

- [ ] **Step 6: Reconstruct desktop run approvals from lifecycle**

Replace the empty implementation of `get_run_approvals` with a scoped database query that returns requested approvals plus the latest terminal lifecycle (`46011`, `46012`, or `46013`). Add a Tauri command test for pending, granted, denied, and delegated records.

- [ ] **Step 7: Run the complete decision suite**

Run:

```bash
. ./bin/activate-hermit
cargo test -p buzz-relay approval_
cargo test -p buzz-db workflow
cargo test --manifest-path desktop/src-tauri/Cargo.toml workflows
```

Expected: all pass.

- [ ] **Step 8: Commit transactional decisions**

```bash
git add crates/buzz-relay/src/handlers/command_executor.rs \
  crates/buzz-relay/src/handlers/ingest.rs crates/buzz-relay/src/handlers/event.rs \
  crates/buzz-relay/src/state.rs crates/buzz-db/src/workflow.rs \
  crates/buzz-db/src/event.rs crates/buzz-sdk/src/builders.rs \
  desktop/src-tauri/src/commands/workflows.rs
git commit -m "feat: add atomic approval delegation"
```

---

## Task 4: Add Closed Push Wake Classes

**Files:**

- Modify: `crates/buzz-relay/src/handlers/push_lease.rs`
- Modify: `crates/buzz-relay/src/push_runtime.rs`
- Modify: `crates/buzz-relay/src/nip11.rs`
- Modify: `crates/buzz-push-gateway/src/model.rs`
- Modify: `crates/buzz-push-gateway/src/apns.rs`
- Modify: `crates/buzz-push-gateway/src/http.rs`
- Modify: `docs/nips/NIP-PL.md`

- [ ] **Step 1: Add failing relay descriptor and lease-policy tests**

Require:

```rust
assert_eq!(PUSH_KINDS, &[7, 9, 1059, 40002, 40007, 46010]);
assert_eq!(TIME_SENSITIVE_KINDS, &[46010]);
```

Test that a `time_sensitive` subscription containing any other kind is rejected, while a default subscription for `9`, `40002`, and `1059` is accepted. Require the NIP-11 descriptor to publish the gateway origin, wake classes, and exact kind arrays.

- [ ] **Step 2: Add failing gateway wire tests**

Define a closed wire enum:

```rust
#[serde(rename_all = "snake_case")]
pub enum WakeClass {
    Default,
    TimeSensitive,
}
```

Require `DeliveryRequest` to deserialize only these values. Assert exact compiled payload bytes:

```json
{"aps":{"alert":{"body":"Zion needs attention"},"sound":"default"}}
```

and:

```json
{"aps":{"alert":{"body":"Zion needs attention"},"sound":"default","interruption-level":"time-sensitive"}}
```

Reject an arbitrary class or payload field.

- [ ] **Step 3: Run focused red tests**

Run:

```bash
. ./bin/activate-hermit
cargo test -p buzz-relay push_
cargo test -p buzz-push-gateway model
cargo test -p buzz-push-gateway apns
```

Expected: class, descriptor, and payload assertions fail.

- [ ] **Step 4: Implement relay class propagation**

Rename `URGENT_KINDS` to `TIME_SENSITIVE_KINDS`, retain legacy `urgent` input only as a normalized alias if existing leases use it, and serialize `WakeClass` into the relay-to-gateway request. Derive the class exclusively from the validated lease subscription that matched the event.

- [ ] **Step 5: Implement the gateway payload allowlist**

Replace `APNS_RECONNECT_PAYLOAD` with two constants selected by `WakeClass`. Keep `apns-push-type: alert` and priority `10`; never accept alert text, sound, badge, category, or interruption level from a relay request.

- [ ] **Step 6: Update NIP-PL documentation**

Document:

- gateway discovery through the relay's NIP-11 descriptor;
- the two accepted wake classes;
- the exact generic text and headers;
- approval-only time-sensitive eligibility;
- mention kind `40002`;
- the absence of application content in the delivery request.

- [ ] **Step 7: Run push subsystem checks**

Run:

```bash
. ./bin/activate-hermit
cargo fmt --all -- --check
cargo test -p buzz-relay push_
cargo test -p buzz-push-gateway
cargo test -p buzz-db push
```

Expected: all pass.

- [ ] **Step 8: Commit wake classes**

```bash
git add crates/buzz-relay/src/handlers/push_lease.rs \
  crates/buzz-relay/src/push_runtime.rs crates/buzz-relay/src/nip11.rs \
  crates/buzz-push-gateway/src/model.rs crates/buzz-push-gateway/src/apns.rs \
  crates/buzz-push-gateway/src/http.rs docs/nips/NIP-PL.md
git commit -m "feat: add generic Zion push wake classes"
```

---

## Task 5: Build the Phone-Side Watch Inbox and Actions

**Files:**

- Create: `mobile/lib/shared/watch/watch_models.dart`
- Create: `mobile/lib/shared/watch/watch_inbox_mapper.dart`
- Create: `mobile/lib/shared/watch/watch_action_service.dart`
- Create: `mobile/lib/shared/watch/watch_action_ledger.dart`
- Create: `mobile/lib/shared/watch/watch_agent_candidates.dart`
- Create: `mobile/lib/app/watch_companion_coordinator.dart`
- Create: `mobile/test/shared/watch/watch_inbox_mapper_test.dart`
- Create: `mobile/test/shared/watch/watch_action_service_test.dart`
- Create: `mobile/test/shared/watch/watch_action_ledger_test.dart`
- Create: `mobile/test/shared/watch/watch_agent_candidates_test.dart`
- Create: `mobile/test/app/watch_companion_coordinator_test.dart`
- Modify: `mobile/lib/features/activity/activity_provider.dart`
- Modify: `mobile/lib/features/channels/channels_provider.dart`
- Modify: `mobile/lib/features/channels/mentions/mention_candidates_provider.dart`
- Modify: `mobile/lib/features/channels/send_message_provider.dart`
- Create: `mobile/test/features/channels/send_message_provider_test.dart`

- [ ] **Step 1: Write pure-model and mapper tests**

Define wire-safe models with explicit schema versioning:

```dart
enum WatchItemKind { approval, directMessage, mention }
enum WatchActionKind { approve, deny, passToAgent, openOnPhone }
enum WatchActionState { queued, sending, succeeded, failed }
```

Test approval-first ordering, newest-first ordering within a kind, 20-item truncation, 2,000-scalar truncation, terminal-lifecycle removal, active-community filtering, and stable item IDs based on the source event ID.

- [ ] **Step 2: Run the mapper tests red**

Run:

```bash
cd mobile
flutter test test/shared/watch/watch_inbox_mapper_test.dart
```

Expected: imports fail because the watch companion models do not exist.

- [ ] **Step 3: Implement immutable models and mapper**

Keep the models and pure mapper in `shared/watch` so all feature modules can consume them without cross-feature imports. The app-layer coordinator may read activity, channel, and presence providers and pass their values into the pure mapper. Map:

- pending `46010` without a matching `46011`, `46012`, or `46013` to approval;
- DM kind `9` with another participant to direct message;
- kind `40002` or a `p`-tagged message to mention.

Carry only item ID, community ID, channel ID, title, plain-text preview, created time, source event ID, approval digest, and eligible action metadata.

- [ ] **Step 4: Add red action-builder and idempotency tests**

Test that:

- approve signs kind `46030`;
- deny signs kind `46031`;
- Pass signs kind `46032` with exactly one target `p` tag;
- all actions bind the `d` approval digest;
- duplicate watch action IDs reuse the previous result and publish once;
- stale community/item/approval state fails without signing;
- successful terminal actions remove the item locally after relay acceptance.

- [ ] **Step 5: Implement the phone-owned action service**

Use `SignedEventRelay` to publish the SDK-equivalent command builders. Persist a bounded action ledger under application support with action ID, community ID, source item ID, result, and timestamp. Expire ledger entries after seven days and cap at 200 entries.

- [ ] **Step 6: Add eligible Pass candidate tests**

Build candidates in `shared/watch/watch_agent_candidates.dart` from plain agent-directory and presence inputs supplied by the app-layer coordinator. Require registered agents, actor invocability, a different requester/actor, and non-expired online/away presence. Sort online before away, then recent use, then display name.

- [ ] **Step 7: Ensure DM events carry recipient tags**

Add a failing `send_message` test for DMs, then add `p` tags for every other DM participant in addition to explicit mentions. Deduplicate tags and retain `h` channel scope. This makes recipient-gated NIP-PL subscriptions match normal DMs.

- [ ] **Step 8: Run mobile unit tests and commit**

Run:

```bash
cd mobile
dart format --output=none --set-exit-if-changed lib test
flutter test test/shared/watch
flutter test test/app/watch_companion_coordinator_test.dart
flutter test test/features/channels
```

Then:

```bash
git add mobile/lib/shared/watch mobile/lib/app/watch_companion_coordinator.dart \
  mobile/test/shared/watch mobile/test/app/watch_companion_coordinator_test.dart \
  mobile/lib/features/activity/activity_provider.dart \
  mobile/lib/features/channels/channels_provider.dart \
  mobile/lib/features/channels/mentions/mention_candidates_provider.dart \
  mobile/lib/features/channels/send_message_provider.dart \
  mobile/test/features/channels
git commit -m "feat: derive Zion Watch inbox and actions"
```

---

## Task 6: Enroll APNs and Maintain NIP-PL Leases

**Files:**

- Create: `mobile/lib/shared/apple/apple_companion_channel.dart`
- Create: `mobile/lib/shared/watch/push_descriptor.dart`
- Create: `mobile/lib/shared/watch/push_lease_coordinator.dart`
- Create: `mobile/test/shared/watch/push_descriptor_test.dart`
- Create: `mobile/test/shared/watch/push_lease_coordinator_test.dart`
- Create: `mobile/ios/Runner/KeychainStore.swift`
- Create: `mobile/ios/Runner/PushEnrollmentService.swift`
- Create: `mobile/ios/Runner/AppleCompanionPlugin.swift`
- Create: `mobile/ios/RunnerTests/PushEnrollmentServiceTests.swift`
- Modify: `mobile/ios/Runner/AppDelegate.swift`
- Modify: `mobile/ios/Runner/Runner.entitlements`
- Modify: `mobile/ios/Runner.xcodeproj/project.pbxproj`
- Modify: `mobile/lib/features/settings/settings_page.dart`
- Modify: `mobile/lib/app.dart`

- [ ] **Step 1: Add red descriptor and lease tests**

Parse only a valid NIP-11 push descriptor with HTTPS gateway origin, relay executor pubkey, app profile, supported classes, and kind allowlists. Reject HTTP origins, unknown profiles, absent executor keys, or a descriptor that permits time-sensitive delivery for a non-approval kind.

Test the exact signed kind `30350` lease sets:

- time-sensitive: `46010` plus `#p` self;
- default messages: `9,40002` plus `#p` self;
- default gift wraps: `1059` plus `#p` self.

Every lease must include `d`, `executor`, and `expiration`; endpoint grants are NIP-44 encrypted for the relay executor.

- [ ] **Step 2: Implement Dart descriptor and coordinator**

The coordinator must:

1. remain idle until the authenticated user explicitly enables notifications;
2. fetch NIP-11 from the active relay origin;
3. request an endpoint grant from the existing gateway through the native channel;
4. publish or renew the three replaceable leases;
5. renew before expiry and after an APNs token epoch change;
6. revoke/expire the old community leases on community switch and sign-out;
7. expose deterministic status to Settings without prompting at app launch.

- [ ] **Step 3: Add red native tests**

Use protocol-injected fakes for `UNUserNotificationCenter`, `DCAppAttestService`, `URLSession`, and Keychain. Test:

- permission is requested only from the explicit enable call;
- APNs registration waits for granted authorization;
- challenge, attestation, enrollment, and delegation bind the same app profile and endpoint epoch;
- the token is stored in Keychain, not user defaults;
- a token rotation increments the epoch and yields a new endpoint grant;
- generic foreground notifications do not reveal remote body content.

- [ ] **Step 4: Implement native enrollment**

`PushEnrollmentService` owns authorization, `registerForRemoteNotifications`, APNs token conversion, App Attest key creation/attestation/assertion, gateway requests, and Keychain persistence. `AppleCompanionPlugin` exposes narrow methods:

```swift
enableNotifications
notificationStatus
currentEndpointGrant
revokeEndpoint
```

and an event stream for APNs token/grant epoch changes. Remove the current startup authorization request from `AppDelegate`.

- [ ] **Step 5: Configure entitlements by build configuration**

Add:

```xml
<key>aps-environment</key>
<string>$(APS_ENVIRONMENT)</string>
<key>com.apple.developer.usernotifications.time-sensitive</key>
<true/>
<key>com.apple.developer.devicecheck.appattest-environment</key>
<string>$(APP_ATTEST_ENVIRONMENT)</string>
```

Set Debug to development and Profile/Release to production values. Do not hardcode the Apple team or provisioning profile.

- [ ] **Step 6: Add Settings onboarding**

Add a Notifications & Watch row that shows Off, Enabling, Active, Needs Attention, or Unsupported. Tapping Enable presents the system prompt through the coordinator; denial shows a concise path to iOS Settings. The rest of the app remains usable without notifications.

- [ ] **Step 7: Run Dart and Runner tests**

Run:

```bash
cd mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test test/shared/watch
```

Use XcodeBuildMCP to run the Runner test target on an iOS simulator after showing and configuring session defaults.

- [ ] **Step 8: Commit push enrollment**

```bash
git add mobile/lib/shared/apple mobile/lib/shared/watch mobile/test/shared/watch \
  mobile/lib/features/settings/settings_page.dart \
  mobile/lib/app.dart mobile/ios/Runner mobile/ios/RunnerTests \
  mobile/ios/Runner.xcodeproj/project.pbxproj
git commit -m "feat: enroll Zion iOS push notifications"
```

---

## Task 7: Add the Credential-Free Phone/Watch Bridge

**Files:**

- Create: `mobile/ios/Shared/WatchWireModels.swift`
- Create: `mobile/ios/Runner/WatchSessionBridge.swift`
- Create: `mobile/ios/RunnerTests/WatchWireModelsTests.swift`
- Create: `mobile/ios/RunnerTests/WatchSessionBridgeTests.swift`
- Modify: `mobile/ios/Runner/AppleCompanionPlugin.swift`
- Modify: `mobile/lib/shared/apple/apple_companion_channel.dart`
- Modify: `mobile/lib/shared/watch/watch_models.dart`
- Modify: `mobile/lib/app/watch_companion_coordinator.dart`

- [ ] **Step 1: Add red Codable contract tests**

Define a versioned envelope:

```swift
struct WatchSnapshotEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let communityID: String
    let generatedAt: Date
    let items: [WatchInboxItem]
}
```

Define action request/result envelopes with a UUID action ID. Test JSON round trips, unknown schema rejection, 20-item enforcement, 2,000-scalar enforcement, and absence of keys named `secret`, `privateKey`, `token`, `endpointGrant`, or `nsec`.

- [ ] **Step 2: Add red bridge behavior tests**

With a fake `WCSession`, test:

- reachable watch receives `sendMessage`;
- unreachable watch receives `transferUserInfo` plus the latest `updateApplicationContext`;
- snapshot replacement is atomic;
- duplicate action IDs are forwarded once;
- malformed/oversized messages are rejected;
- community clear sends an empty snapshot;
- actions received while Flutter is unavailable persist in the protected phone queue and replay when the engine is ready.

- [ ] **Step 3: Implement shared wire models**

Keep these models Foundation-only so both Runner and ZionWatch targets compile them. Use explicit coding keys and an exact schema version. Store only the minimum fields from Task 5.

- [ ] **Step 4: Implement `WatchSessionBridge`**

Activate the default WatchConnectivity session when supported. Persist the latest snapshot and incoming action queue with `NSFileProtectionCompleteUntilFirstUserAuthentication`. Acknowledge receipt immediately, but report success only after Flutter returns the relay result.

- [ ] **Step 5: Connect Flutter to the bridge**

Add native channel methods:

```dart
Future<void> publishWatchSnapshot(WatchSnapshot snapshot)
Future<void> clearWatchSnapshot()
Stream<WatchActionRequest> watchActions()
Future<void> completeWatchAction(WatchActionResult result)
```

The provider rebuilds snapshots only for the active community and routes actions through the idempotent service from Task 5.

- [ ] **Step 6: Run bridge checks and commit**

Run:

```bash
cd mobile
flutter test test/shared/watch
flutter analyze
```

Use XcodeBuildMCP to run `WatchWireModelsTests` and `WatchSessionBridgeTests`.

Then:

```bash
git add mobile/ios/Shared mobile/ios/Runner/WatchSessionBridge.swift \
  mobile/ios/Runner/AppleCompanionPlugin.swift mobile/ios/RunnerTests \
  mobile/lib/shared/apple mobile/lib/shared/watch \
  mobile/lib/app/watch_companion_coordinator.dart
git commit -m "feat: bridge Zion iPhone and Apple Watch"
```

---

## Task 8: Add the watchOS Target and Focused Queue UI

**Files:**

- Create: `mobile/ios/scripts/configure_zion_watch.rb`
- Create: `mobile/scripts/check-watch-target.mjs`
- Create: `mobile/ios/ZionWatch/ZionWatchApp.swift`
- Create: `mobile/ios/ZionWatch/WatchInboxStore.swift`
- Create: `mobile/ios/ZionWatch/WatchInboxCache.swift`
- Create: `mobile/ios/ZionWatch/WatchConnectivityClient.swift`
- Create: `mobile/ios/ZionWatch/WatchTheme.swift`
- Create: `mobile/ios/ZionWatch/FocusedQueueView.swift`
- Create: `mobile/ios/ZionWatch/ApprovalDetailView.swift`
- Create: `mobile/ios/ZionWatch/MessageDetailView.swift`
- Create: `mobile/ios/ZionWatch/PassAgentPickerView.swift`
- Create: `mobile/ios/ZionWatch/ActionConfirmationView.swift`
- Create: `mobile/ios/ZionWatch/Assets.xcassets/Contents.json`
- Create: `mobile/ios/ZionWatchTests/WatchInboxStoreTests.swift`
- Create: `mobile/ios/ZionWatchTests/WatchInboxCacheTests.swift`
- Modify: `mobile/ios/Runner.xcodeproj/project.pbxproj`
- Create: `mobile/ios/Runner.xcodeproj/xcshareddata/xcschemes/ZionWatch.xcscheme`

- [ ] **Step 1: Add a red project-structure check**

`check-watch-target.mjs` must inspect the Xcode project and fail unless it finds:

- an application target named `ZionWatch`;
- a unit-test target named `ZionWatchTests`;
- `SDKROOT = watchos`;
- `WATCHOS_DEPLOYMENT_TARGET = 26.0`;
- `TARGETED_DEVICE_FAMILY = 4`;
- bundle ID `$(BUNDLE_IDENTIFIER).watchkitapp`;
- `WKCompanionAppBundleIdentifier = $(BUNDLE_IDENTIFIER)`;
- Runner embeds the watch product and depends on ZionWatch;
- the shared `WatchWireModels.swift` belongs to both app targets;
- a shared ZionWatch scheme exists.

Run:

```bash
cd mobile
node scripts/check-watch-target.mjs
```

Expected: failure because the watch target is absent.

- [ ] **Step 2: Write a reproducible target-configurator**

Use CocoaPods' bundled `xcodeproj` gem in `configure_zion_watch.rb`. The script must be idempotent: running it twice produces no project diff. It adds target membership, embed/dependency relationships, per-configuration build settings, product references, test host configuration, and the shared scheme without changing Runner's signing identity or deployment target.

- [ ] **Step 3: Run the configurator and structural check**

Run:

```bash
cd mobile/ios
GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.17.0/libexec \
  ruby scripts/configure_zion_watch.rb
cd ..
node scripts/check-watch-target.mjs
```

Expected: the check passes and a second configurator run leaves `project.pbxproj` unchanged.

- [ ] **Step 4: Add red store/cache tests**

Test:

- approvals appear before DMs and mentions;
- the queue is limited to 20;
- loading cached data produces an offline/read-only state;
- a new snapshot replaces older community data;
- approve/deny/pass require confirmation;
- action submission disables repeat taps and exposes queued/success/failure state;
- a terminal success removes the item;
- Pass requires selecting one eligible agent;
- Open on iPhone sends a deep-link action.

- [ ] **Step 5: Implement the focused queue**

Build the approved minimalist palette:

- true black background;
- violet approval accent;
- green approve action;
- red deny action;
- neutral white/gray typography;
- one compact card per item;
- Digital Crown scrolling;
- large tap targets and VoiceOver labels;
- no settings, identity, compose, relay, or agent-management screens.

Approval detail shows prompt, requesting workflow/agent, age, and Approve/Deny/Pass. Message detail shows sender, channel, preview, and Open on iPhone. Pass picker shows only phone-supplied eligible agents.

- [ ] **Step 6: Implement watch connectivity and protected cache**

The watch client reads application context at launch, receives live snapshots/results, stores the bounded non-secret snapshot using protected file storage, and forwards action envelopes. If the phone is unreachable, display Queued and let WatchConnectivity deliver later.

- [ ] **Step 7: Build and test with XcodeBuildMCP**

First call `session_show_defaults`. Configure the worktree project, ZionWatch scheme, and a paired iPhone/Apple Watch simulator from `list_sims`. Then run the watch build/test workflow. Do not use `flutter build` or `flutter run`.

Expected: ZionWatch and ZionWatchTests compile and tests pass with the watchOS 26 SDK.

- [ ] **Step 8: Commit the watch target and UI**

```bash
git add mobile/ios/scripts mobile/scripts/check-watch-target.mjs \
  mobile/ios/ZionWatch mobile/ios/ZionWatchTests mobile/ios/Shared \
  mobile/ios/Runner.xcodeproj
git commit -m "feat: add Zion Watch focused queue"
```

---

## Task 9: Verify End-to-End Behavior and Failure Recovery

**Files:**

- Create: `mobile/test/app/watch_companion_flow_test.dart`
- Create: `docs/testing/zion-watch-runbook.md`
- Modify: `crates/buzz-test-client/tests/e2e_relay.rs`
- Modify: `mobile/README.md`

- [ ] **Step 1: Add relay end-to-end tests**

Create an approval gate and verify kind `46010` is readable by the exact approver. Execute approve, deny, and Pass paths. For Pass, assert the original approval is terminal, the old run is cancelled, the delegated lifecycle is present, one target task reply exists, and thread counters are correct.

- [ ] **Step 2: Add the phone/watch orchestration test**

With fake relay and native bridge providers, test:

1. approval arrives and sorts first;
2. phone publishes the watch snapshot;
3. watch action arrives with a stable action ID;
4. phone signs and publishes the command;
5. relay acceptance produces success;
6. phone removes the item and sends the result/snapshot;
7. repeating the same action ID does not republish.

- [ ] **Step 3: Document real-device validation**

The runbook must distinguish:

- source checks;
- simulator build/tests;
- signed iPhone installation;
- paired physical Watch installation;
- APNs sandbox enrollment;
- App Attest real-device behavior;
- background/unreachable-phone transfer;
- time-sensitive entitlement and Focus-mode delivery.

Include exact evidence to record: app/version/build, device/watchOS versions, relay community, event IDs, APNs environment, timestamps, and screenshot/log locations. Mark App Attest/APNs/physical Watch validation as incomplete until performed on signed hardware.

- [ ] **Step 4: Run repository quality gates**

Run:

```bash
. ./bin/activate-hermit
cargo fmt --all -- --check
cargo test -p buzz-core
cargo test -p buzz-sdk
cargo test -p buzz-workflow
cargo test -p buzz-db
cargo test -p buzz-relay
cargo test -p buzz-push-gateway
cargo test -p buzz-test-client --test e2e_relay
just mobile-check
just mobile-test
git diff --check
```

Use XcodeBuildMCP to rerun Runner and ZionWatch build/tests. If PostgreSQL or Redis is unavailable, record that infrastructure blocker separately and still complete all unit, compile, mobile, and Xcode gates.

- [ ] **Step 5: Review the implementation against the design**

Verify every requirement in `docs/superpowers/specs/2026-07-26-zion-watch-companion-design.md` has implementation or test evidence. Review changed files manually for unfinished markers. Review public type names across Rust, Dart, and Swift; verify wire schema values and event kind numbers match exactly; inspect the staged diff; run a secret-pattern scan over newly added files.

- [ ] **Step 6: Commit verification assets**

```bash
git add crates/buzz-test-client/tests/e2e_relay.rs \
  mobile/test/app/watch_companion_flow_test.dart \
  mobile/README.md docs/testing/zion-watch-runbook.md
git commit -m "test: verify Zion Watch companion flow"
```

- [ ] **Step 7: Update Linear and prepare branch handoff**

Post to MI8-5:

- commit list;
- exact passing/failing gates;
- simulator evidence;
- explicit hardware/APNs/App Attest validation status;
- remaining blockers with owners;
- branch/worktree path.

Then use `superpowers:finishing-a-development-branch` to present the verified branch options. Do not push, create a PR, merge, or install on hardware without the user's explicit authorization.
