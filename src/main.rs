//! `nexus-core` binary entrypoint.
//!
//! This file intentionally plays the role of a "composition root":
//! it wires together independent modules (crypto, task, and a small domain
//! model) without embedding infrastructure concerns into the domain logic.
//!
//! The core research primitive here is the "Thermodynamic Slashing" penalty:
//!
//! \[
//!   S = n \cdot R
//! \]
//!
//! where:
//! - `n` is latency (delay),
//! - `R` is energy consumption,
//! - `S` is the penalty score.

mod crypto;
mod task;

use crate::crypto::hash_node_id;
use crate::task::InferenceTask;

#[derive(Debug, Clone)]
struct Node {
    /// Unique identifier for the node (e.g., public key, hostname, or logical ID).
    id: String,
    /// Network latency component `n` (delay). Units are up to your model.
    latency_n: f64,
    /// Energy consumption component `R`. Units are up to your model.
    energy_r: f64,
}

impl Node {
    /// Compute the "Thermodynamic Slashing" penalty score.
    ///
    /// Formula:
    ///     S = n * R
    ///
    /// Notes:
    /// - If you later expand this into on-chain / consensus logic,
    ///   consider enforcing bounds and validating input (e.g., non-negative values).
    fn calculate_slashing_penalty(&self) -> f64 {
        self.latency_n * self.energy_r
    }
}

fn main() {
    // A "fast" node: low latency and low energy usage.
    let fast_node = Node {
        id: "node-fast".to_string(),
        latency_n: 5.0,
        energy_r: 2.0,
    };

    // A "bad" node: high latency and high energy usage.
    let slow_energy_hungry_node = Node {
        id: "node-slow-energy-hungry".to_string(),
        latency_n: 120.0,
        energy_r: 18.0,
    };

    // Infrastructure boundary: derive privacy-preserving identifiers that can be used
    // to link tasks to a node without exposing the raw node ID everywhere.
    let fast_node_id_hash = hash_node_id(&fast_node.id);
    let slow_node_id_hash = hash_node_id(&slow_energy_hungry_node.id);

    // Application boundary: model an AI inference request associated with each node.
    // In a real system, tasks would be transported over the network and scheduled.
    let fast_task = InferenceTask::new(
        "task-fast-001",
        "nexus-infer-mock-v1",
        "Summarize the thermodynamic slashing concept in one paragraph.",
        256,
        fast_node_id_hash,
    );

    let slow_task = InferenceTask::new(
        "task-slow-001",
        "nexus-infer-mock-v1",
        "Run a long chain-of-thought style reasoning workload (mock).",
        1024,
        slow_node_id_hash,
    );

    let s_fast = fast_node.calculate_slashing_penalty();
    let s_bad = slow_energy_hungry_node.calculate_slashing_penalty();

    // Print raw scores for easy inspection in the terminal.
    println!("Thermodynamic Slashing penalty scores (S = n * R)");
    println!(
        "- {}: n = {:.3}, R = {:.3} => S = {:.3}",
        fast_node.id, fast_node.latency_n, fast_node.energy_r, s_fast
    );
    println!(
        "- {}: n = {:.3}, R = {:.3} => S = {:.3}",
        slow_energy_hungry_node.id,
        slow_energy_hungry_node.latency_n,
        slow_energy_hungry_node.energy_r,
        s_bad
    );

    // Show how the "task layer" can be linked to node identity via hashing,
    // without requiring the task to hold the raw node ID.
    println!();
    println!("Inference task linkage (mock)");
    println!(
        "- task_id = {}, requester_node_id_hash = {}, model = {}, max_tokens = {}, created_at_unix_ms = {}",
        fast_task.id,
        fast_task.requester_node_id_hash,
        fast_task.model,
        fast_task.max_tokens,
        fast_task.created_at_unix_ms
    );
    println!(
        "- task_id = {}, requester_node_id_hash = {}, model = {}, max_tokens = {}, created_at_unix_ms = {}",
        slow_task.id,
        slow_task.requester_node_id_hash,
        slow_task.model,
        slow_task.max_tokens,
        slow_task.created_at_unix_ms
    );

    // Compare and explain which node is penalized more.
    if s_fast < s_bad {
        println!(
            "Result: '{}' has the lower penalty (better efficiency/performance).",
            fast_node.id
        );
    } else if (s_fast - s_bad).abs() < f64::EPSILON {
        println!("Result: both nodes have the same penalty.");
    } else {
        println!(
            "Result: '{}' has the lower penalty (better efficiency/performance).",
            slow_energy_hungry_node.id
        );
    }
}
