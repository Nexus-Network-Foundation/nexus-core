# Contributing to Nexus Network

Nexus Network is building the future of **“Can’t be evil” AI**: inference that becomes trustworthy not by promises, but by **cryptography, verification, and incentives**. If you want to help shape sovereign infrastructure for verified AI, you are welcome here.

This repository is an evolving PoC intended to become a **safe, scalable implementation platform** for external contributors. The non-negotiable source of truth for `nexus-core` architecture and invariants is [`TECHNICAL_WHITEPAPER.md`](TECHNICAL_WHITEPAPER.md).

Related reading:

- [`WHITE_PAPER.md`](WHITE_PAPER.md): Vision, architecture narrative, and roadmap (partner/investor-facing)
- [`README.md`](README.md): Quick start, Docker, and “Test the Integrity” tutorial (including `NEXUS_SIMULATE_FRAUD=1`)
- [`DOCS/GOOD_FIRST_ISSUES.md`](DOCS/GOOD_FIRST_ISSUES.md): Ready-to-file issues for new contributors

---

## Welcome

Contributions that make Nexus **more verifiable, more private, and more operable** are especially valuable. Areas that matter early:

- Strong integrity signals (verification rigor, evidence, auditability)
- Privacy-by-design (E2EE, key management, least-knowledge routing)
- Production readiness (metrics, tracing, health probes, predictable resource usage)

---

## Development setup

### Prerequisites

- **Rust** (stable): `rustup` recommended
- **CMake**: required because `llama-cpp-2` builds llama.cpp from source
  - macOS: `brew install cmake`
  - Linux: `apt/yum/pacman` equivalent
- Optional: Docker / Docker Compose for multi-node demos

### Build and run `nexus-core`

From the repository root:

```bash
cd nexus-core
cargo build --release
```

Apple Silicon (Metal acceleration), if you have it enabled in your environment:

```bash
cd nexus-core
cargo run --release --features metal -- --server
```

### Run the end-to-end demo

From the repository root:

```bash
./scripts/bootstrap.sh
```

Legacy wrapper:

```bash
./demo.sh
```

### Common environment variables

- `NEXUS_GGUF_PATH`: GGUF model path (recommended under `nexus-core/models/...`)
- `NEXUS_MODEL_ID`: model identifier (demo default: `nexus-infer-v1`)
- `NEXUS_REST_LISTEN`: REST bind address (default: `127.0.0.1:8080`)
- `NEXUS_API_KEY`: REST API key
- `NEXUS_VERIFICATION_RATE`: verification sampling rate (default: `1.0`)

---

## Coding standards (non-negotiables)

In addition to idiomatic Rust, Nexus has architectural constraints that protect scalability and correctness. These are enforced by policy, review, and CI.

- **Do not block the libp2p swarm loop**: inference and heavy I/O must run in `spawn_blocking` or a dedicated worker model.
- **Avoid hot-path allocations and clones**: prefer bounded buffers, explicit limits, and predictable memory.
- **Keep CI green**: `cargo fmt`, `cargo clippy --all-targets --all-features -D warnings`, `cargo test`.
- **Respect security invariants**: E2EE should not leak plaintext prompts; integrity checks must remain verifiable and auditable.

If you are unsure whether a change violates an invariant, defer to [`TECHNICAL_WHITEPAPER.md`](TECHNICAL_WHITEPAPER.md) and align the implementation accordingly.

---

## Contribution flow

1. **Fork** the repository on GitHub.
2. Create a **feature branch** from `main`:

```bash
git checkout -b feat/<short-topic>
```

3. Make changes with a tight scope and add/adjust docs where helpful.
4. Run local checks (from `nexus-core/`):

```bash
cargo fmt
cargo clippy --all-targets --all-features -D warnings
cargo test
```

5. Open a **Pull Request** with:
   - A short architectural summary (“what and why”)
   - A test plan (commands you ran)
   - Notes on performance / hot-path impact if relevant

---

## Community

For technical discussion, design debates, and contributor support, join Discord:

- `https://discord.gg/Ay3EcSBRan`

---

## Good first issues

If you’re new to the codebase, start here:

- [`DOCS/GOOD_FIRST_ISSUES.md`](DOCS/GOOD_FIRST_ISSUES.md)

These issues are curated to be self-contained, high-impact, and aligned with Nexus’s core invariants (privacy, integrity, and operability).

