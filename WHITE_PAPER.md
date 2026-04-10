# Nexus Network — White Paper

**Version:** 1.0 (public release narrative)  
**Date:** April 2026  
**Companion document:** [`TECHNICAL_WHITEPAPER.md`](TECHNICAL_WHITEPAPER.md) — authoritative implementation blueprint for `nexus-core`

---

## Abstract

Nexus Network is a **sovereign infrastructure layer for verified artificial intelligence**: a decentralized inference network where **prompt privacy**, **cryptographic integrity of outputs**, and **economic incentives** align honest execution with user trust. Unlike centralized API providers that see every prompt and control every policy, Nexus routes work across independent nodes while preserving verifiability and penalizing abuse.

This document states **vision, threat model at a high level, architecture, and roadmap** for investors and partners. Engineering invariants, performance budgets, and module boundaries are specified in the technical blueprint.

---

## 1. Problem

Centralized inference creates structural risk:

- **Privacy:** Operators can read, log, and monetize user prompts and outputs.
- **Integrity:** Users cannot independently verify that a response was produced by an agreed model under agreed conditions.
- **Single points of failure:** Outages, policy changes, and regional blocks affect entire ecosystems.
- **Misaligned economics:** Value accrues to rent-seeking intermediaries rather than to nodes that actually run compute under physical constraints.

Decentralized alternatives often trade away **quality**, **latency**, or **auditability**. Nexus targets a middle path: **edge-first execution**, **explicit verification paths**, and **economic feedback** so the network self-corrects.

---

## 2. Vision

**Nexus Network: The Sovereign Infrastructure for Verified AI.**

- Users and applications retain **sovereignty** over prompts (end-to-end encryption toward designated executors) and **policy** (who may execute, under what tier, with what verification depth).
- The network provides **integrity signals** (signatures, sampling-based verification, and slashing) so malicious or lazy behavior is **detectable and costly**.
- **Portability** (containers, reproducible builds, optional GPU paths) lowers the barrier for operators to join from any serious environment.

---

## 3. High-Level Architecture

### 3.1 Components

| Role | Responsibility |
|------|----------------|
| **Client** | Submits inference requests; may expose a REST façade; holds user-facing keys for E2EE where applicable. |
| **Seed** | Bootstrap and scheduling metadata; should not need plaintext prompts when E2EE routing is used. |
| **Executor** | Runs local inference (e.g. GGUF via llama.cpp); returns signed results; subject to verification and economics. |

### 3.2 Networking

- **libp2p** (TCP, Noise, Yamux) for transport security and peer identity.
- **Gossipsub** for discovery-style broadcast in PoC; **request/response** for directed task and result delivery as the system hardens.
- **Design rule:** the swarm event loop must not be blocked by inference or heavy I/O; workers run off the hot path.

### 3.3 Inference

- **llama-cpp-2** binds to llama.cpp for high-performance local inference.
- Models are loaded once per process where possible; bounded concurrency preserves predictable memory.

### 3.4 Security & Trust Layers (Progressive)

1. **Transport:** Encrypted channels between peers.  
2. **Result signing:** Executors sign outputs; clients reject invalid signatures.  
3. **E2EE prompts:** X25519 + AES-GCM style encryption so intermediaries cannot read prompt content in transit (PoC path).  
4. **Optimistic verification:** Sampled double-checks flag low-quality or adversarial outputs.  
5. **Slashing & economics:** Penalties and rewards stored in a durable ledger (SQLite + append-only audit log in PoC), steering the network toward honest work.

---

## 4. Economic Model (PoC → Production)

**Virtual balance** and **tiering** reward verified successful work (e.g. higher tier → higher reward). **Slashing** reduces stake for verification failures, decryption errors, timeouts, and signature violations. An **append-only audit trail** (`nexus_audit.log`) records economic events for transparency and future on-chain bridges.

Production will require formal tokenomics, Sybil resistance, and dispute windows; the PoC demonstrates **mechanism existence** and **observability**.

### 4.1 Mathematical formalization (PoC rules)

We state the **core** PoC rules in closed form. Implementation details (integer rounding, SQLite updates, and secondary penalties) are specified in `nexus-core` and [`TECHNICAL_WHITEPAPER.md`](TECHNICAL_WHITEPAPER.md); the symbols below describe the **intended economic semantics**.

**Slashing (verification failure — fraud / lazy output).**  
Let \(B_{\mathrm{current}}\) denote the executor’s virtual balance immediately before the penalty is applied. The slash magnitude for a **failed verification** event is proportional to the current balance:

\[
S = B_{\mathrm{current}} \times 0.5
\]

Equivalently, the post-slash balance is \(B' = B_{\mathrm{current}} - S = 0.5\,B_{\mathrm{current}}\). Other failure classes (timeouts, decryption errors) may apply **fixed** decrements in code; \(S\) above is the **dominant multiplicative** rule for adversarial or inconsistent outputs caught by \(\mathcal{V}\).

**Reward (successful verified task).**  
Let \(T_{\mathrm{weight}}\) be the **tier multiplier** associated with the executor’s quality tier (higher tier ⇒ larger weight). Let \(\varphi\) be the **base task reward** per verified completion. Then the credit applied to balance is:

\[
R = T_{\mathrm{weight}} \times \varphi
\]

In the reference PoC, discrete tier levels (e.g. Gold / Silver / Bronze) instantiate concrete values of \(T_{\mathrm{weight}}\) while \(\varphi\) is normalized to the unit reward scale used by the ledger.

**Verification integrity (binary outcome).**  
Optimistic verification and double-checking induce a deterministic or randomized test procedure \(\mathcal{V}\) that maps an observed execution outcome (signatures, text quality checks, consistency with a shadow sample, etc.) to a binary signal:

\[
\mathcal{V} : \Omega \rightarrow \{0,\,1\}
\]

where **1** denotes **success** (verified, eligible for \(R\)) and **0** denotes **failure** (ineligible for \(R\); triggers \(S\) and audit events as defined in policy). The domain \(\Omega\) is the space of attestable evidence in the PoC (signed payloads, timing, decryption status).

---

## 5. Roadmap

| Phase | Focus |
|-------|--------|
| **Now** | PoC: P2P mesh, REST, E2EE path, optimistic verification, slashing hooks, Docker. |
| **Next** | Prompt commitments, stronger identity binding, metrics and tracing, destination-controlled result routing at scale. |
| **Later** | zkML / proof-backed inference, governance, cross-chain incentive bridges. |

---

## 6. Risks & Disclaimers

- This repository is **research and engineering PoC** software, not a regulated financial product or production SLA.
- Security properties depend on correct deployment, key management, and future hardening (rate limits, spam resistance, formal verification of crypto).
- Model licensing, data residency, and compliance remain **operator responsibilities**.

---

## 7. References

- [`TECHNICAL_WHITEPAPER.md`](TECHNICAL_WHITEPAPER.md) — `nexus-core` ultimate blueprint (performance, CI, boundaries).
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — developer onboarding and code map.
- [`README.md`](README.md) — quick start, Docker, integrity test.

---

*© Nexus Network contributors. Licensed per repository `LICENSE` where applicable.*
