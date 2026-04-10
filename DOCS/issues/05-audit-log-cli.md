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
