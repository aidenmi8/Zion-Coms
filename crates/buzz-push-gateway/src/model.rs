//! Closed wire types for the stateful gateway.

use serde::{Deserialize, Serialize};

pub const MAX_REQUEST_BYTES: usize = 8 * 1024;
pub const MAX_GRANT_BYTES: usize = 4096;
pub const MAX_ENDPOINT_HEX_BYTES: usize = 512;
pub const APNS_DEFAULT_PAYLOAD: &[u8] =
    br#"{"aps":{"alert":{"body":"Zion needs attention"},"sound":"default"}}"#;
pub const APNS_TIME_SENSITIVE_PAYLOAD: &[u8] =
    br#"{"aps":{"alert":{"body":"Zion needs attention"},"sound":"default","interruption-level":"time-sensitive"}}"#;
pub const WIRE_VERSION: u8 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum AppProfile {
    BuzzIosProduction,
    BuzzIosSandbox,
}
impl AppProfile {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::BuzzIosProduction => "buzz-ios-production",
            Self::BuzzIosSandbox => "buzz-ios-sandbox",
        }
    }
}

/// Closed relay-to-gateway wake class.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WakeClass {
    /// Ordinary generic alert.
    Default,
    /// Approval-only generic Time Sensitive alert.
    TimeSensitive,
}

/// Relay request. It deliberately has no application-payload field:
/// the gateway selects one of two compiled-in generic APNs payloads.
/// `endpoint_grant` is opaque authenticated ciphertext minted by the gateway
/// sealing key and persisted with the relay-owned lease.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeliveryRequest {
    pub v: u8,
    pub endpoint_grant: String,
    pub request_id: uuid::Uuid,
    pub expires_at: i64,
    pub wake_class: WakeClass,
}

/// Opaque delivery capability plaintext. It contains no APNs token: the random
/// delegation id resolves through durable authority state, while the remaining
/// fields are authenticated fences that make stale or cross-relay use fail.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EndpointGrant {
    pub v: u8,
    pub delegation_id: uuid::Uuid,
    pub relay_pubkey: String,
    pub app_profile: AppProfile,
    pub endpoint_epoch: i64,
    pub generation: i64,
    pub expires_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InstallationChallengeRequest {
    pub v: u8,
}

#[derive(Debug, Clone, Serialize)]
pub struct InstallationChallengeResponse {
    pub challenge_id: uuid::Uuid,
    pub challenge: String,
    pub expires_at: i64,
}

/// Direct app enrollment. `attestation` is Apple's CBOR object and `key_id` is
/// the App Attest key identifier, both base64 encoded. The attested key is the
/// installation authority; no second application signing key is introduced.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InstallationEnrollRequest {
    pub v: u8,
    pub challenge_id: uuid::Uuid,
    pub challenge: String,
    pub key_id: String,
    pub attestation: String,
    pub app_profile: AppProfile,
    pub endpoint: String,
    pub endpoint_epoch: i64,
    pub expires_at: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct InstallationEnrollResponse {
    pub installation_handle: uuid::Uuid,
    pub endpoint_epoch: i64,
    pub expires_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DelegationRequest {
    pub v: u8,
    pub challenge_id: uuid::Uuid,
    pub challenge: String,
    pub installation_handle: uuid::Uuid,
    pub endpoint_epoch: i64,
    pub generation: i64,
    pub relay_pubkey: String,
    pub not_before: i64,
    pub expires_at: i64,
    pub assertion: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DelegationResponse {
    pub endpoint_grant: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RotateEndpointRequest {
    pub v: u8,
    pub challenge_id: uuid::Uuid,
    pub challenge: String,
    pub installation_handle: uuid::Uuid,
    pub endpoint_epoch: i64,
    pub new_endpoint_epoch: i64,
    pub endpoint: String,
    pub assertion: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RevokeDelegationRequest {
    pub v: u8,
    pub challenge_id: uuid::Uuid,
    pub challenge: String,
    pub installation_handle: uuid::Uuid,
    pub relay_pubkey: String,
    pub generation: i64,
    pub assertion: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RevokeInstallationRequest {
    pub v: u8,
    pub challenge_id: uuid::Uuid,
    pub challenge: String,
    pub installation_handle: uuid::Uuid,
    pub endpoint_epoch: i64,
    pub new_endpoint_epoch: i64,
    pub assertion: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct MutationResponse {
    pub status: &'static str,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "status", deny_unknown_fields)]
pub enum DeliveryResponse {
    Accepted,
    InvalidEndpoint {
        generation: i64,
        invalid_at: Option<i64>,
    },
    Retry {
        retry_after_seconds: Option<i64>,
    },
}

#[derive(Debug, Clone, Serialize)]
pub struct ErrorBody {
    pub error: &'static str,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delivery_request_accepts_only_closed_wake_classes() {
        for (raw, expected) in [
            (
                r#"{"v":1,"endpoint_grant":"grant","request_id":"00000000-0000-0000-0000-000000000000","expires_at":10,"wake_class":"default"}"#,
                WakeClass::Default,
            ),
            (
                r#"{"v":1,"endpoint_grant":"grant","request_id":"00000000-0000-0000-0000-000000000000","expires_at":10,"wake_class":"time_sensitive"}"#,
                WakeClass::TimeSensitive,
            ),
        ] {
            let request: DeliveryRequest = serde_json::from_str(raw).expect("closed request");
            assert_eq!(request.wake_class, expected);
        }
        assert!(serde_json::from_str::<DeliveryRequest>(
            r#"{"v":1,"endpoint_grant":"grant","request_id":"00000000-0000-0000-0000-000000000000","expires_at":10,"wake_class":"critical"}"#
        )
        .is_err());
        assert!(serde_json::from_str::<DeliveryRequest>(
            r#"{"v":1,"endpoint_grant":"grant","request_id":"00000000-0000-0000-0000-000000000000","expires_at":10,"wake_class":"default","payload":{"aps":{}}}"#
        )
        .is_err());
    }
}
