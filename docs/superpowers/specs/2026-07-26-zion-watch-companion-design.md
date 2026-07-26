# Zion Watch Companion Design

**Date:** 2026-07-26
**Status:** Approved design, pending written-spec review

## Summary

Zion Watch is a deliberately small, dependent watchOS companion for the existing
Zion Flutter iPhone app. It gives the owner a focused queue containing pending
agent approval requests, direct messages, and direct mentions. Approval requests
can be approved, denied, or passed to another eligible agent; ordinary messages
are readable and can be opened on iPhone.

The iPhone remains the sole trust and network boundary. It owns the Nostr secret,
relay connection, push enrollment, event signing, and authoritative action
results. The watch stores only a bounded presentation cache and opaque action
identifiers. It never receives an `nsec`, approval token/hash, relay credential,
APNs token, or push-gateway capability.

The first release targets watchOS 26 and uses the selected **Focused Queue**
design: black surfaces, violet emphasis, green approval, red denial, and a
violet Pass action. It supports only the active iPhone community and has no
complication, independent relay connection, chat composer, settings hierarchy,
or Android work.

## Existing Foundation and Required Gaps

The repository already has the relevant primitives:

- Workflow approval command kinds `46030` and `46031`.
- Approval-request lifecycle kinds `46010`–`46012`.
- A mobile Activity feed that reads approval events addressed to the current
  user.
- A NIP-PL push matcher and stateful APNs gateway.
- A mobile relay session, signing path, channel-agent directory, and
  user-profile cache.

The feature must finish these incomplete paths rather than build around them:

- The mobile app does not enroll with APNs/App Attest or publish NIP-PL leases.
- The workflow engine still needs to persist and emit actionable `46010`
  requests, and desktop's approval reconstruction is also marked incomplete.
- Push matching omits the current `40002` stream-message kind.
- The APNs gateway currently emits one default generic wake and does not map
  validated urgent delivery classes to a Time Sensitive payload.
- The iOS workspace contains only the Flutter `Runner` scheme and no watch
  target.

## Product Experience

### Focused Queue

The root screen shows at most 20 cached items for the iPhone's active community:

1. Pending approval requests, newest first.
2. Direct messages and direct mentions, newest first.

Each row shows item type, sender or requesting agent, relative time, and one
short line of context. A violet edge marks pending approvals. The header shows
the active community name and pending-item count. Empty, loading, waiting for
iPhone, and retry states replace the list instead of layering extra navigation.

Selecting an approval opens a scrollable detail containing the requesting
agent, channel, timestamp, request text, expiry, and three full-width actions:
Approve, Deny, and Pass to Agent. Selecting a message opens its readable body
and an Open on iPhone button. Reading on watch records only local watch
presentation state; it does not advance the channel's authoritative read marker.
Snapshot bodies are plain text capped at 2,000 Unicode scalars. Truncated items
show a visible continuation marker and Open on iPhone; attachments, code
payloads, and media remain phone-only.

### Confirmation and Results

Every mutating action requires a confirmation screen:

- **Approve:** names the agent and exact request being approved.
- **Deny:** names the request being stopped.
- **Pass:** first presents a short contextual agent list, then names the chosen
  destination on the confirmation screen.

The Pass picker contains current-channel agents that the owner is allowed to
invoke, excludes the requesting agent, hides unavailable agents, and orders the
remaining candidates by active status, recent use, then display name. If no
eligible agent exists, Pass is unavailable and the detail offers Open on iPhone.
For v1, available means the agent has a non-expired online or away presence;
offline or unknown-presence agents are omitted.

After confirmation, the watch shows progress until the iPhone returns an
authoritative relay outcome. Relay acceptance produces a success haptic and a
brief Approved, Denied, or Passed result before the resolved item leaves the
queue. A request resolved elsewhere becomes Already handled. A retryable
failure remains visible with Retry and Open on iPhone actions.

### Notifications and Privacy

Remote notifications remain content-free. Both default and Time Sensitive APNs
payloads say only **“Zion needs attention”** and contain no event ID, sender,
channel, request text, agent identity, or community identifier. Opening the
watch app reveals cached or freshly fetched content only after normal device
unlock and privacy behavior.

Notifications expose no Approve, Deny, or Pass buttons. Those actions exist
only after the user opens the watch app and reviews an identified request.

Approval requests use the Time Sensitive delivery class. Direct mentions and
DMs use the default class and respect Focus. Notification authorization is
requested from a user-initiated mobile onboarding surface for alerts, sounds,
and badges; startup must not display a permission prompt.

## Architecture

### Target and Ownership

Add a dependent SwiftUI watch target to
`mobile/ios/Runner.xcworkspace`:

- Product and scheme: `Zion Watch`.
- Deployment target: watchOS 26.0.
- Bundle identifier: `$(BUNDLE_IDENTIFIER).watchkitapp`.
- `WKCompanionAppBundleIdentifier`: the resolved Runner bundle identifier.
- `WKRunsIndependentlyOfCompanionApp`: false.
- Runner embeds the watch product in its archive and carries Push Notifications
  plus Time Sensitive Notifications capabilities.

The target must inherit the existing configurable bundle/team setup and must not
hardcode the private release bundle ID or signing team. No App Group or widget
target is needed for v1; Watch Connectivity provides the only cross-device
transport.

The iPhone side has three boundaries:

1. A native Swift push-enrollment service for APNs device-token and App Attest
   operations.
2. A native Swift `WCSession` bridge that transports versioned snapshots and
   action envelopes.
3. A Flutter/Dart coordinator that owns relay reads, Nostr signing, active
   community state, and conversion between relay events and watch DTOs.

The watch uses small SwiftUI views with an app-owned observable store. It owns
presentation state and its pending-action queue, but no service credentials.
Its snapshot and pending-action files use complete file protection and are
deleted on sign-out, community replacement, or companion unpairing.

### Versioned Watch Wire Contract

Watch Connectivity transports JSON `Data` inside property-list-compatible
dictionaries. Every payload includes `version: 1`.

`WatchInboxSnapshot` contains:

- `communityID`, `communityName`, and `generatedAt`.
- Up to 20 `WatchInboxItem` values.
- Per-item eligible-agent summaries only where Pass is available.

`WatchInboxItem` contains:

- Opaque `itemID` and type: `approval`, `directMessage`, or `mention`.
- Title, sender label, optional channel label, body, creation time, and expiry.
- Presentation status and allowed actions.
- Eligible agents with pubkey, display name, availability, and sort rank.

It intentionally omits signing material and the approval token/hash. The phone
persists the community-scoped item-to-approval mapping in Keychain-backed
storage and deletes it on sign-out or community removal.

`WatchActionRequest` contains:

- `actionID` UUID, `communityID`, and `itemID`.
- Action: `approve`, `deny`, or `pass`.
- `targetAgentPubkey` only for Pass.

`WatchActionResult` contains the same action/item IDs, an outcome
(`accepted`, `alreadyResolved`, `rejected`, or `retryable`), a safe display
message, and resolution time.

The iPhone sends the latest complete snapshot with
`updateApplicationContext`. The watch uses `sendMessage` for immediate refreshes
and actions while reachable. If an action cannot receive an immediate reply,
the watch persists it and queues it with `transferUserInfo`. Duplicate delivery
is expected and safe.

The iPhone keeps a seven-day action ledger keyed by `actionID`. It stores the
signed event/result before returning success, so a lost reply or background
redelivery returns the original outcome instead of signing a second action.

### Push Enrollment and Wake Classes

The native iPhone service:

1. Registers for APNs after permission is granted.
2. Uses `DCAppAttestService` to enroll or recover the installation with the
   gateway advertised by the relay's NIP-11 descriptor.
3. Stores the App Attest key ID, installation handle, endpoint epoch, and
   rotation metadata in Keychain.
4. Returns only the opaque gateway grant/profile metadata required by the Dart
   lease coordinator.

The Dart coordinator builds and publishes the encrypted, author-only
kind-`30350` lease. It renews before expiry, rotates when APNs changes the device
token, revokes on sign-out, and republishes on active-community changes.

The lease has three narrow subscriptions:

- `kinds:[46010]` + `#p:[self]`, class `time_sensitive`.
- `kinds:[9,40002]` + `#p:[self]`, class `default`.
- `kinds:[1059]` + `#p:[self]`, class `default`.

Relay push policy adds `40002` to the eligible kind set and `46010` to the
urgent kind set through a new migration and matching tests.

The relay-to-gateway request gains a closed wake-class enum. The gateway maps
only validated `default` and `time_sensitive` values to two compile-time APNs
payload constants containing the same generic alert and default sound. The
latter adds Apple's Time Sensitive interruption level; neither payload accepts
application-supplied content. NIP-PL documentation, formal invariants, and tests
change from “one byte constant” to “one member of a fixed class-keyed payload
allowlist.”

## Approval and Pass Contracts

### Actionable Approval Requests

Completing a workflow `RequestApproval` step must atomically:

1. Create the hashed approval record.
2. Suspend the workflow run at the requesting step.
3. Persist and fan out a kind-`46010` approval-request event.

The request event contains:

- `d`: approval token SHA-256 hash, never the raw token.
- `p`: exact intended human approver.
- `h`: workflow channel when channel-scoped.
- `workflow`, `run`, and `step` identifiers.
- `expiration`: request expiry.
- `agent`: requesting agent pubkey when applicable.
- Human-readable request content.

Only a pending, unexpired `46010` event with the current user's `p` tag and a
valid token-hash mapping is actionable on watch. Other feed items remain
view-only.

Approve and Deny continue to publish user-signed `46030` and `46031` command
events with the token hash in `d`. Mobile gets builders that explicitly accept
an already-hashed approval reference, preventing accidental double hashing.

### Atomic Pass to Agent

Add:

- Command kind `46032`: approval pass/reassign.
- Lifecycle kind `46013`: approval delegated.
- Approval status `delegated` plus `delegated_to_pubkey`.

The user-signed `46032` event includes the token hash (`d`), target agent (`p`),
source request (`e`), channel (`h`), and empty content. The relay validates that
the caller may act on the pending request, the source is channel-scoped, and the
target is a different, invocable agent in that channel.

One database transaction then:

1. Persists the idempotent command.
2. Marks the approval `delegated`, recording actor and target.
3. Cancels the original workflow run with a structured delegated reason.
4. Persists a relay-signed kind-`9` task message in the same channel, linked to
   the source request and explicitly `p`-tagged to the selected agent.
5. Persists the `46013` lifecycle event and updates thread counters when the
   task is a reply.

Only after commit does normal dispatch fan out the task and lifecycle events.
This guarantees that Pass cannot cancel the original request without creating
the replacement task, or create duplicate work while leaving the approval
pending.

## Failure Handling

- **iPhone unreachable:** retain the action as Waiting for iPhone and deliver it
  in the background. The user can cancel only before phone acknowledgement.
- **Relay offline:** the phone returns retryable; it does not report success or
  construct a replacement local state.
- **Expired/resolved request:** return alreadyResolved, refresh the snapshot,
  and remove the stale action.
- **Community changed:** reject the action without signing, clear the old watch
  snapshot, and request the new active-community snapshot.
- **Ineligible pass target:** reject without mutating the approval and refresh
  the eligible-agent list.
- **Partial push setup:** manual watch launch still refreshes through the phone;
  settings show push unavailable without blocking normal mobile use.
- **Malformed or future wire version:** ignore safely and show Update Zion on
  iPhone rather than attempting a best-effort decode.

Logs and metrics must never include message text, approval hashes, APNs tokens,
gateway grants, Nostr secrets, or full pubkeys.

## Testing and Acceptance

### Automated

- Rust unit/integration tests cover new kinds, approval-request emission,
  authorization, expiry/races, atomic Pass rollback, delegated lifecycle,
  task-message fan-out, thread counters, push-kind eligibility, wake-class
  confinement, and fixed APNs payload selection.
- Dart tests cover event-to-watch mapping, active-community resets, NIP-PL lease
  filters/renewal/revocation, hashed approval builders, agent eligibility, and
  action-ledger replay.
- Swift iPhone/watch tests cover wire decoding, snapshot ordering/limits,
  cache replacement, queued-action deduplication, confirmation state, and every
  result/error state.
- SwiftUI accessibility tests verify labels, non-color status cues, Dynamic
  Type, and minimum interactive target behavior.
- Gates include focused Rust tests, relay/database integration tests,
  `just mobile-check`, `just mobile-test`, the watch scheme build/tests,
  `git diff --check`, and the relevant full `just ci` gate.

### Paired-device acceptance

Use a physical iPhone and paired Apple Watch; Watch Connectivity background
transfers are not fully represented by the simulator.

The release candidate passes when:

1. A private generic alert reaches the watch while the phone app is not
   foregrounded, with no message/request data in the APNs payload.
2. Opening Zion Watch shows cached content immediately, refreshes through the
   phone, and never displays another community's items.
3. Approve and Deny each require confirmation and show success only after relay
   acceptance.
4. Pass shows the contextual agent picker, atomically resolves the original,
   and wakes exactly the selected agent with the linked task.
5. An offline watch action delivers once after reconnection despite duplicate
   transport attempts.
6. Expired, remotely resolved, ineligible-target, relay-failure, and community
   switch states produce the specified recovery UI.
7. Open on iPhone routes to the source message/request.

## Rollout

Deploy the relay approval/push changes and gateway payload-class support before
shipping the companion. Validate APNs/App Attest and NIP-PL against staging,
then distribute the iPhone/watch pair through TestFlight to a small owner group.
Monitor content-free counters for enrollment success, lease renewal, wake
acceptance, watch sync latency, queued-action age, and action outcomes.

If the relay does not advertise NIP-PL, the watch remains usable as an
on-demand phone-backed inbox without remote alerts. Independent watch
networking, complications, replies, full channel browsing, voice composition,
and multi-community switching are explicit post-v1 work.

## References

- [Apple: Setting up a watchOS project](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project)
- [Apple: Transferring data with Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- [Apple: Enabling and receiving watchOS notifications](https://developer.apple.com/documentation/watchos-apps/enabling-and-receiving-notifications)
- [Buzz NIP-PL](../../nips/NIP-PL.md)
