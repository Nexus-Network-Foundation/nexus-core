# Good First Issues (copy for GitHub)

Maintainers: ensure labels exist once, e.g. `gh label create "good first issue" --color "7057ff" --description "Welcome for new contributors"` (skip if already present).

Bulk-create (requires `gh auth login`):

```bash
cd "$(git rev-parse --show-toplevel)"
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  title="${line%%|*}"
  body_file="${line#*|}"
  body_file="${body_file#"${body_file%%[![:space:]]*}"}"
  gh issue create --title "$title" --body-file "$body_file" --label "good first issue"
done < DOCS/good_first_issue_manifest.txt
```

Manifest and per-issue bodies live in `DOCS/good_first_issue_manifest.txt` and `DOCS/issues/*.md`.

Alternatively paste each **Title** and **Body** below into GitHub’s “New issue” UI.

---

## Issue 1 — Implement Prometheus metrics for nexus-core

**Labels:** `good first issue`, `enhancement`, `observability`

**Body:**

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

---

## Issue 2 — Add Web UI dashboard for node health and verification stats

**Labels:** `good first issue`, `enhancement`, `frontend`

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

---

## Issue 3 — Add `/healthz` and `/readyz` HTTP endpoints

**Labels:** `good first issue`, `enhancement`, `ops`

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

---

## Issue 4 — Publish OpenAPI 3.0 spec for the REST API

**Labels:** `good first issue`, `documentation`, `api`

### Summary
Author `openapi.yaml` (or `.json`) describing `POST /v1/chat/completions`, auth header, example request/response including `metadata.verification_status` and `metadata.virtual_balance`.

### Why
SDK generation, partner integration, and API reviews all start from a machine-readable contract.

### Scope / hints
- Align field names with `nexus-core/src/rest.rs` and `DOCS/API.md` if present.
- Include error responses (401, 429, 5xx) as stubs.

### Acceptance criteria
- [ ] Spec committed under `DOCS/` or repo root, linked from README.
- [ ] Validated with `swagger-cli validate` or redocly in CI (optional follow-up).

---

## Issue 5 — CLI: parse and filter `nexus_audit.log` (JSONL)

**Labels:** `good first issue`, `tooling`, `cli`

### Summary
A small Rust binary (e.g. `nexus-audit-tool` under `nexus-core` or a workspace member) that reads `nexus_audit.log`, filters by `reason`, peer, or time range, and prints pretty JSON or CSV.

### Why
Contributors and auditors need to inspect slashing/reward events without `jq` one-liners.

### Scope / hints
- Stream large files; do not load entire log into memory.
- Reuse event shapes from `nexus-core/src/audit.rs` where possible (or document the JSON schema in the tool `--help`).

### Acceptance criteria
- [ ] `cargo run --bin ... -- --help` documents flags.
- [ ] Example in README or CONTRIBUTING referencing `NEXUS_AUDIT_PATH`.

---
