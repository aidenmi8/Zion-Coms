//! Action sink trait — interface for workflow side-effects.
//!
//! The relay implements [`ActionSink`] to provide direct DB access to the
//! executor, replacing the HTTP loopback pattern.

use std::future::Future;
use std::pin::Pin;

use buzz_core::tenant::CommunityId;
use chrono::{DateTime, Utc};
use serde_json::Value as JsonValue;
use uuid::Uuid;

/// Fully resolved approval request handed from the workflow executor to its
/// side-effect sink.
///
/// The sink owns token generation and durable persistence so the executor
/// cannot suspend a run without a corresponding actionable request.
#[derive(Debug, Clone, PartialEq)]
pub struct ApprovalRequest {
    /// Community that owns the workflow and approval.
    pub community_id: CommunityId,
    /// Workflow definition identifier.
    pub workflow_id: Uuid,
    /// Workflow run identifier.
    pub run_id: Uuid,
    /// Step identifier from the workflow definition.
    pub step_id: String,
    /// Zero-based step index.
    pub step_index: i32,
    /// Exact pubkey or `@display-name` of the intended human approver.
    pub approver_spec: String,
    /// Human-readable approval prompt.
    pub message: String,
    /// Absolute expiry for the pending approval.
    pub expires_at: DateTime<Utc>,
    /// Workflow channel when the workflow is channel-scoped.
    pub channel_id: Option<Uuid>,
    /// Hex pubkey of the workflow owner.
    pub owner_pubkey: String,
    /// Execution trace completed before this approval gate.
    pub execution_trace: JsonValue,
}

/// Durable identity returned after an approval request commits.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApprovalReceipt {
    /// Relay-signed kind-46010 request event ID.
    pub request_event_id: String,
}

/// Errors from action sink operations.
#[derive(Debug, thiserror::Error)]
pub enum ActionSinkError {
    /// An input parameter is malformed (e.g. invalid UUID).
    #[error("invalid input: {0}")]
    InvalidInput(String),
    /// The target channel does not exist.
    #[error("channel not found: {0}")]
    ChannelNotFound(String),
    /// The target channel is archived.
    #[error("channel is archived: {0}")]
    ChannelArchived(String),
    /// Nostr event construction or signing failed.
    #[error("event construction failed: {0}")]
    EventBuild(String),
    /// A database operation failed.
    #[error("database error: {0}")]
    Database(String),
    /// Message content is empty or whitespace-only.
    #[error("empty message content")]
    EmptyContent,
}

impl From<ActionSinkError> for crate::WorkflowError {
    fn from(e: ActionSinkError) -> Self {
        crate::WorkflowError::WebhookError(e.to_string())
    }
}

/// Interface for workflow actions that produce side effects.
///
/// Implemented by the relay to provide direct DB/event access to the executor.
/// This replaces the HTTP loopback where the executor POSTed to the relay's
/// REST API (which failed with 401 auth errors).
///
/// Returns `Pin<Box<dyn Future>>` for dyn-compatibility — required because
/// `WorkflowEngine` stores `Arc<dyn ActionSink>`.
pub trait ActionSink: Send + Sync {
    /// Post a message to a channel on behalf of a workflow owner.
    ///
    /// - `community_id`: the server-resolved community that owns the workflow
    ///   run driving this side effect. The relay-signed message is published
    ///   under *this* community, never the deployment/default tenant — the run
    ///   carries its owning community so a workflow in community B posts into B
    ///   even though the side effect has no inbound connection to bind.
    /// - `channel_id`: UUID string of the target channel
    /// - `text`: message body (must not be empty/whitespace-only)
    /// - `author_pubkey`: hex-encoded pubkey of the workflow owner (used for
    ///   the `p` attribution tag; the relay keypair signs the event)
    ///
    /// Returns the event ID hex string on success.
    fn send_message(
        &self,
        community_id: CommunityId,
        channel_id: &str,
        text: &str,
        author_pubkey: &str,
    ) -> Pin<Box<dyn Future<Output = Result<String, ActionSinkError>> + Send + '_>>;

    /// Atomically persist an actionable approval request and suspend its run.
    ///
    /// Implementations generate and hash the secret approval token internally,
    /// persist only its digest, and return the public request event ID.
    fn request_approval(
        &self,
        request: ApprovalRequest,
    ) -> Pin<Box<dyn Future<Output = Result<ApprovalReceipt, ActionSinkError>> + Send + '_>>;
}
