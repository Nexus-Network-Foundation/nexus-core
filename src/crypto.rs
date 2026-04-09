//! Crypto boundary (infrastructure-style module).
//!
//! In a production Web3 stack, this module would host:
//! - key management
//! - signature verification
//! - hashing utilities with strict domain separation
//!
//! For this prototype, we only provide a minimal SHA-256 helper used to
//! deterministically derive a hashed node identifier.

use sha2::{Digest, Sha256};

/// Hash a node ID using SHA-256 and return it as a lowercase hex string.
///
/// This is intentionally "dumb" and deterministic:
/// - no salt
/// - no domain separation tag
/// - no versioning
///
/// Those should be added once you define the protocol-level ID scheme.
pub fn hash_node_id(node_id: &str) -> String {
    let digest = Sha256::digest(node_id.as_bytes());
    hex::encode(digest)
}

