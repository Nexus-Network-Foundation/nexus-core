//! Application boundary (use-case-style module).
//!
//! This module models an "AI inference request" that might be routed through
//! the network. In a real system, this would likely include:
//! - request/response signing
//! - pricing / fee market fields
//! - model capability constraints
//! - serialization formats for networking

use std::time::{SystemTime, UNIX_EPOCH};

/// A minimal representation of an AI inference request.
///
/// This is a "mock" domain object meant to demonstrate how the penalty logic
/// can be connected to a real workload primitive.
#[derive(Debug, Clone)]
pub struct InferenceTask {
    /// Globally unique ID for the task (mocked as a string here).
    pub id: String,
    /// The model name / identifier (e.g., "nexus-infer-v1").
    pub model: String,
    /// The user prompt / input payload (kept as plain text for this mock).
    pub prompt: String,
    /// Upper bound on tokens to generate (or to process), depending on protocol.
    pub max_tokens: u32,
    /// Hashed identifier of the requesting node (privacy-preserving primitive).
    pub requester_node_id_hash: String,
    /// Creation timestamp (Unix time in milliseconds).
    pub created_at_unix_ms: u128,
}

impl InferenceTask {
    /// Create a new inference task with a current timestamp.
    pub fn new(
        id: impl Into<String>,
        model: impl Into<String>,
        prompt: impl Into<String>,
        max_tokens: u32,
        requester_node_id_hash: impl Into<String>,
    ) -> Self {
        let created_at_unix_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis();

        Self {
            id: id.into(),
            model: model.into(),
            prompt: prompt.into(),
            max_tokens,
            requester_node_id_hash: requester_node_id_hash.into(),
            created_at_unix_ms,
        }
    }
}

