### Summary
Add minimal HTTP endpoints for orchestration: liveness (`/healthz`) and readiness (`/readyz`, e.g. model loaded + swarm started).

### Why
Kubernetes/Docker health checks and load balancers expect these conventions.

### Scope / hints
- Implement in `nexus-core/src/rest.rs` (or a tiny submodule) behind `NEXUS_ENABLE_REST`.
- Keep handlers O(1); no inference in readiness unless explicitly desired (document choice).

### Acceptance criteria
- [ ] Both paths return appropriate HTTP status codes (200 vs 503).
- [ ] Document behavior in `DOCS/API.md` or README.
- [ ] Tests or manual checklist in PR description.
