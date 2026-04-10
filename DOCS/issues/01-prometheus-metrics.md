### Summary
Expose operational metrics (HTTP, P2P, inference queue depth, verification outcomes) via a Prometheus scrape endpoint, without blocking the libp2p swarm loop.

### Why
Operators and integrators need time-series visibility before production hardening.

### Scope / hints
- Follow `TECHNICAL_WHITEPAPER.md`: metrics collection must stay off the hot path; use bounded channels or atomic counters where appropriate.
- Suggested crate: `metrics` + `metrics-exporter-prometheus`, or `prometheus` crate with a dedicated listener task.
- Start with: REST request count/latency, active peers, tasks in flight, verification pass/fail counters, optional GGUF load flag.

### Acceptance criteria
- [ ] `GET /metrics` (or separate port via env, e.g. `NEXUS_METRICS_LISTEN`) returns valid Prometheus text format.
- [ ] Document env vars in `README.md` or `CONTRIBUTING.md`.
- [ ] `cargo clippy --all-targets --all-features -D warnings` passes.
