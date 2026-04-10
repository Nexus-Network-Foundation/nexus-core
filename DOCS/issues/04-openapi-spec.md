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
