//! Canonical Zion product identity and compatibility aliases.

/// Human-visible product name emitted by first-party surfaces.
pub const PRODUCT_NAME: &str = "Zion";

/// Human-visible default relay name.
pub const RELAY_NAME: &str = "Zion Relay";

/// Human-visible default relay description.
pub const RELAY_DESCRIPTION: &str = "Zion — private team communication relay";

/// Canonical deep-link scheme emitted by Zion.
pub const CANONICAL_URL_SCHEME: &str = "zion";

/// Legacy deep-link scheme accepted for compatibility.
pub const LEGACY_URL_SCHEME: &str = "buzz";

/// Public source repository used by release and relay metadata.
pub const RELEASE_REPOSITORY_URL: &str = "https://github.com/aidenmi8/Zion-Coms";

/// Public Git HTTP authentication realm.
pub const GIT_AUTH_REALM: &str = "zion";

/// Git smart-HTTP agent capability emitted by the relay.
pub const GIT_AGENT_CAPABILITY: &str = "zion-git";

/// Read a canonical environment variable, falling back to its legacy alias.
///
/// An explicitly present canonical value wins even when it is empty.
pub fn env_alias(canonical: &str, legacy: &str) -> Option<String> {
    std::env::var(canonical)
        .ok()
        .or_else(|| std::env::var(legacy).ok())
}
