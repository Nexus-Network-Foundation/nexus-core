### Summary
A small static or SSR dashboard that calls existing REST/stats endpoints (and optionally `/metrics`) to show node tier, balance, recent verification status, and peer count.

### Why
Lowers the barrier for demos and external contributors to “see” the network state.

### Scope / hints
- Prefer a **separate** `web/` or `dashboard/` package (Vite + React, or plain HTML + fetch) so `nexus-core` stays lean.
- Read-only by default; no secrets in the bundle.
- Optional: Docker Compose service that proxies to `NEXUS_REST_LISTEN`.

### Acceptance criteria
- [ ] README section “Web dashboard” with build/run instructions.
- [ ] Works against local `./scripts/bootstrap.sh` stack.
- [ ] No blocking calls on the Rust swarm thread (UI is out-of-process).
