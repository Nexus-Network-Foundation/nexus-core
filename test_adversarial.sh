#!/usr/bin/env bash
# Local adversarial Gossipsub smoke test: seed + honest client + adversarial client.
# Safe to run from any cwd: paths are resolved from this script's location (repo root).
set -euo pipefail

# Repository root = directory containing this script (must live at repo root).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${ROOT}/nexus-core"
LOG_DIR="${ROOT}/.test_adversarial_logs"
BIN_PATH="${CORE_DIR}/target/debug/nexus-core"

API_KEY="${NEXUS_API_KEY:-steve-secret-key}"
export NEXUS_API_KEY="${API_KEY}"

cleanup() {
  echo "[test_adversarial] cleanup: stopping prior nexus-core processes..."
  pkill -f '[t]arget/.*/nexus-core' 2>/dev/null || true
  pkill -f '/nexus-core' 2>/dev/null || true
  sleep 1
}

if [[ ! -d "${CORE_DIR}" ]]; then
  echo "[test_adversarial] ERROR: nexus-core not found at ${CORE_DIR}" >&2
  exit 1
fi

cleanup
mkdir -p "${LOG_DIR}"
: >"${LOG_DIR}/seed.log"
: >"${LOG_DIR}/honest.log"
: >"${LOG_DIR}/adv.log"

echo "[test_adversarial] ROOT=${ROOT}"
echo "[test_adversarial] BIN_PATH=${BIN_PATH}"
echo "[test_adversarial] LOG_DIR=${LOG_DIR}"

echo "[test_adversarial] building nexus-core (debug)..."
cargo build -q --manifest-path "${CORE_DIR}/Cargo.toml"

if [[ ! -f "${BIN_PATH}" ]]; then
  echo "[test_adversarial] ERROR: binary not found (build may have failed): ${BIN_PATH}" >&2
  exit 1
fi
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "[test_adversarial] ERROR: binary exists but is not executable: ${BIN_PATH}" >&2
  exit 1
fi

export NEXUS_MOCK_INFERENCE=true
export NEXUS_DISABLE_REPL=true
# Seed reads this so E2EE TaskRoute can pick executors even with model mismatch / low score (adversarial harness).
export NEXUS_E2EE_ROUTE_RELAX=1

echo "[test_adversarial] starting seed (no REST; p2p :50001)..."
(
  PORT=8080 \
    NEXUS_NODE_KEY_PATH="${LOG_DIR}/node_key_seed.bin" \
    NEXUS_DB_PATH="${LOG_DIR}/seed.db" \
    NEXUS_MODE=SEED \
    "${BIN_PATH}" --server
) >>"${LOG_DIR}/seed.log" 2>&1 &
SEED_PID=$!

echo "[test_adversarial] starting honest client REST :8081..."
(
  PORT=8081 \
    NEXUS_NODE_KEY_PATH="${LOG_DIR}/node_key_honest.bin" \
    NEXUS_DB_PATH="${LOG_DIR}/honest.db" \
    NEXUS_MODE=CLIENT \
    "${BIN_PATH}"
) >>"${LOG_DIR}/honest.log" 2>&1 &
HONEST_PID=$!

echo "[test_adversarial] starting adversarial client REST :8082 (--adversarial)..."
(
  PORT=8082 \
    NEXUS_NODE_KEY_PATH="${LOG_DIR}/node_key_adv.bin" \
    NEXUS_DB_PATH="${LOG_DIR}/adv.db" \
    NEXUS_MODE=CLIENT \
    "${BIN_PATH}" --adversarial
) >>"${LOG_DIR}/adv.log" 2>&1 &
ADV_PID=$!

echo "[test_adversarial] PIDs seed=${SEED_PID} honest=${HONEST_PID} adv=${ADV_PID}"
echo "[test_adversarial] logs: ${LOG_DIR}/{seed,honest,adv}.log"
echo "[test_adversarial] waiting for mesh / REST (8s)..."
sleep 8

echo "[test_adversarial] POST http://127.0.0.1:8081/v1/chat/completions ..."
set +e
curl -sS -X POST "http://127.0.0.1:8081/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${NEXUS_API_KEY}" \
  -d '{"model":"nexus-infer-v1","messages":[{"role":"user","content":"adversarial local test"}]}' \
  -w "\n[test_adversarial] HTTP %{http_code}\n"
CURL_ST=$?
set -e
if [[ "${CURL_ST}" -ne 0 ]]; then
  echo "[test_adversarial] WARN: curl failed (exit ${CURL_ST}); check logs and NEXUS_API_KEY" >&2
fi

echo "[test_adversarial] tailing logs (Ctrl+C stops tail only; nodes keep running)..."
echo "[test_adversarial] to stop nodes: pkill -f nexus-core"
tail -f "${LOG_DIR}/seed.log" "${LOG_DIR}/honest.log" "${LOG_DIR}/adv.log"
