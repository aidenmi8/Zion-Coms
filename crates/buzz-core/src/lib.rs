#![deny(unsafe_code)]
#![warn(missing_docs)]
//! `buzz-core` — zero-I/O foundation types for the Buzz relay.
//!
//! Provides [`StoredEvent`], filter matching, kind constants, and event
//! verification. All other Buzz crates depend on this one.

/// NIP-AM: Agent Turn Metric — payload type and encrypt/decrypt helpers.
pub mod agent_turn_metric;
/// Canonical Zion identity and compatibility aliases.
pub mod branding;
/// Channel and membership enums shared across crates.
pub mod channel;
/// NIP-AE Agent Engrams — slug grammar, conversation key, d-tag derivation,
/// body parse/serialize, envelope build/validate, head selection.
pub mod engram;
/// Relay-side error types.
pub mod error;
/// Relay-side event wrapper with verification tracking.
pub mod event;
/// NIP-01 subscription filter matching.
pub mod filter;
/// Git permission types — ref patterns, protection rules, policy evaluation.
pub mod git_perms;
/// Shared invite-link contract constants.
pub mod invite;
/// Buzz kind number registry — custom event type constants.
pub mod kind;
/// Network utilities — SSRF-safe IP classification.
pub mod network;
/// Agent observer frame helpers.
pub mod observer;
/// NIP-AB device pairing — crypto primitives, message types, and errors.
pub mod pairing;
/// Presence status types shared across crates.
pub mod presence;
/// Canonical relay runtime identities.
pub mod relay;
/// Tenant identity — the server-resolved community key carried on scoped paths.
pub mod tenant;
/// Schnorr signature and event ID verification.
pub mod verification;

pub use error::VerificationError;
pub use event::StoredEvent;
pub use nostr::{Event, EventId, Filter, Keys, Kind, PublicKey};
pub use presence::PresenceStatus;
pub use tenant::{normalize_host, CommunityId, TenantContext};
pub use verification::verify_event;

#[cfg(test)]
mod branding_contract_tests {
    use super::branding;
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn public_brand_constants_are_canonical_zion_values() {
        assert_eq!(branding::PRODUCT_NAME, "Zion");
        assert_eq!(branding::RELAY_NAME, "Zion Relay");
        assert_eq!(branding::CANONICAL_URL_SCHEME, "zion");
        assert_eq!(branding::LEGACY_URL_SCHEME, "buzz");
        assert_eq!(
            branding::RELEASE_REPOSITORY_URL,
            "https://github.com/aidenmi8/Zion-Coms"
        );
    }

    #[test]
    fn canonical_environment_value_wins_before_legacy_fallback() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|poison| poison.into_inner());
        std::env::set_var("ZION_RELAY_URL", "wss://canonical.example");
        std::env::set_var("BUZZ_RELAY_URL", "wss://legacy.example");
        let value = branding::env_alias("ZION_RELAY_URL", "BUZZ_RELAY_URL");
        std::env::remove_var("ZION_RELAY_URL");
        std::env::remove_var("BUZZ_RELAY_URL");
        assert_eq!(value.as_deref(), Some("wss://canonical.example"));
    }

    #[test]
    fn legacy_environment_value_remains_a_fallback() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|poison| poison.into_inner());
        std::env::remove_var("ZION_AGENT_MODEL");
        std::env::set_var("BUZZ_AGENT_MODEL", "legacy-model");
        let value = branding::env_alias("ZION_AGENT_MODEL", "BUZZ_AGENT_MODEL");
        std::env::remove_var("BUZZ_AGENT_MODEL");
        assert_eq!(value.as_deref(), Some("legacy-model"));
    }
}

#[cfg(any(test, feature = "test-utils"))]
/// Test helper utilities for creating events and stored events.
pub mod test_helpers {
    use crate::StoredEvent;
    use chrono::Utc;
    use nostr::{EventBuilder, Keys, Kind};

    /// Create a signed test event with the given kind and random keys.
    pub fn make_event(kind: Kind) -> nostr::Event {
        let keys = Keys::generate();
        EventBuilder::new(kind, "test")
            .tags([])
            .sign_with_keys(&keys)
            .expect("sign")
    }

    /// Create a signed test event with the given keys and kind.
    pub fn make_event_with_keys(keys: &Keys, kind: Kind) -> nostr::Event {
        EventBuilder::new(kind, "test")
            .tags([])
            .sign_with_keys(keys)
            .expect("sign")
    }

    /// Create a [`StoredEvent`] wrapper around a test event.
    pub fn make_stored_event(kind: Kind, channel_id: Option<uuid::Uuid>) -> StoredEvent {
        StoredEvent::with_received_at(make_event(kind), Utc::now(), channel_id, true)
    }
}
