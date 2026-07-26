# Zion Watch companion verification

This runbook separates source, simulator, signed-device, and live-notification
evidence. A lower level does not prove a higher one.

## Proof levels

| Level | What it proves | What it does not prove |
|---|---|---|
| Source gates | Rust, Flutter, Swift, project wiring, and deterministic models compile and test | Apple signing, installation, WatchConnectivity, or notification delivery |
| Paired simulators | The embedded watch app launches, renders its focused queue, exchanges snapshots/actions with the simulated iPhone, and preserves action IDs | APNs, App Attest, real background scheduling, wrist notification routing, or Focus behavior |
| Signed iPhone | The Runner archive/install is signed, embeds the watch bundle, and can enroll the phone endpoint | Installation on a physical Watch or wrist delivery |
| Physical iPhone + Watch | End-to-end delivery and action behavior under real device, background, connectivity, and Focus conditions | Production behavior unless the test uses the production APNs profile and production relay |

Do not mark the physical validation complete from simulator screenshots alone.

## Source and simulator gates

From the repository root:

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

The ignored relay tests require a running relay, Postgres, and Redis:

```bash
cargo test -p buzz-test-client --test e2e_relay watch_approval -- --ignored
```

In Xcode or the repository's Xcode automation:

1. Build and test the `Runner` scheme on a paired iPhone simulator.
2. Build and test the `ZionWatch` scheme on its paired Watch simulator.
3. Launch `ZionWatch` and verify the empty state.
4. Seed approval, direct-message, and mention snapshots. Verify approvals sort
   first, followed by the newest direct message or mention.
5. Verify `Approve`, `Deny`, `Pass`, and `Open on iPhone` are only shown where
   valid.
6. Confirm the Runner app embeds one watch app with:
   - iPhone bundle ID: `com.buzz.buzzMobile`
   - Watch bundle ID: `com.buzz.buzzMobile.watchkitapp`
   - Watch companion bundle ID: `com.buzz.buzzMobile`

## Signed iPhone check

Use the intended development or distribution team and profile. Keep the iPhone
unlocked on the Home Screen during installation and first launch.

1. Install the signed Runner build.
2. Confirm the embedded Zion Watch app appears in the Watch app on the phone.
3. Launch Zion, sign in to the intended community, and grant notifications.
4. Record the notification authorization state and endpoint epoch. Never record
   the APNs token, private key, raw endpoint grant, Nostr secret, or App Attest
   assertion.
5. Confirm sign-out and community switching clear the watch snapshot.

This level is incomplete until the watch app is installed on a paired physical
Watch.

## Physical iPhone and Watch matrix

Run each case with the phone nearby because that is the intended operating
model. Repeat the marked delivery cases with the Zion phone app foregrounded,
backgrounded, and force-quit.

| Case | Phone state | Focus | Connectivity | Expected |
|---|---|---|---|---|
| Approval arrival | Foreground/background/force-quit | Off | Normal | One actionable alert and one queue item |
| Mention or DM arrival | Background | Off | Normal | View/Open on iPhone; no approval controls |
| Approve | Background | Off | Normal | One grant command, success confirmation, item removed |
| Deny | Background | Off | Normal | One deny command, success confirmation, item removed |
| Pass | Background | Off | Normal | Eligible-agent picker, one delegated task, original run cancelled |
| Duplicate tap/retry | Background | Off | Normal | Same action ID replays its result; no second relay command |
| Temporary phone loss | Background | Off | Phone unreachable, then restored | Queued action retries and resolves once |
| Focus suppression | Background | Do Not Disturb and one custom Focus | Normal | Behavior matches the configured notification policy and is recorded |
| Open on iPhone | Locked, then unlocked | Off | Normal | Correct `buzz://message` route opens without signing a relay command |
| Sign-out/community switch | Any | Any | Normal | Watch queue clears; old-community actions cannot execute |

For APNs validation, record whether the build used the sandbox or production
application profile. Verify App Attest enrollment and endpoint rotation through
status/epoch only; do not capture credential material.

## Required evidence

Create one record per run containing:

- date, time, and timezone;
- Git commit SHA and whether the worktree was clean;
- Xcode version, build configuration, SDK/runtime versions;
- iPhone and Watch model, OS version, paired state, and device identifiers
  redacted to their last four characters;
- iPhone bundle ID, Watch bundle ID, signing team ID, and profile names;
- APNs environment, notification authorization state, app profile ID, endpoint
  epoch, and App Attest result;
- phone app state, Watch app state, connectivity, and Focus mode;
- source request event ID, stable watch action ID, command event ID, lifecycle
  event ID, and delegated task event ID when applicable;
- relay response, final approval status, original workflow-run status, and
  thread reply/descendant counters;
- observed arrival and action latency;
- paths or links to screenshots, `.xcresult` bundles, and redacted logs;
- pass/fail and any limitation.

Secrets and raw device tokens must be redacted before attaching evidence.

## Completion rule

Software/simulator completion requires all source gates plus both Xcode schemes.
Physical completion additionally requires every row in the device matrix on a
paired iPhone and Apple Watch. Keep the Linear task in progress and label the
remaining physical validation plainly until those records exist.
