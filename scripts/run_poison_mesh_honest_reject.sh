#!/usr/bin/env bash
# 3-node harness: Seed + Adversarial (fixed listen) + Honest (fixed listen).
# Honest <-> Adversarial direct gossip mesh so poisoned results reach Honest even if Seed rejects.
set -euo pipefail
set +m

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${ROOT_DIR}/nexus-core"
KEY_DIR="${ROOT_DIR}/.test_pqc_queue"
SEED_PORT="${NEXUS_SEED_PORT:-50231}"
ADV_PORT="${NEXUS_ADV_MESH_PORT:-50233}"
HONEST_PORT="${NEXUS_HONEST_MESH_PORT:-50234}"
REST_PORT="${NEXUS_MESH_TEST_REST_PORT:-18081}"
DB_PATH="${NEXUS_DB_PATH:-/tmp/nexus_mesh_poison_test.db}"
SEED_LOG="${ROOT_DIR}/.test_pqc_mesh_seed.log"
ADV_LOG="${ROOT_DIR}/.test_pqc_mesh_adv.log"
HONEST_LOG="${ROOT_DIR}/.test_pqc_mesh_honest.log"
API_KEY="${NEXUS_API_KEY:-steve-secret-key}"
MODEL_ID="${NEXUS_MODEL_ID:-nexus-infer-v1}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[mesh-test] ERROR: missing: $1" >&2
    exit 1
  }
}

need_cmd curl
need_cmd jq
need_cmd python3

echo "[mesh-test] ensuring release binary is built..."
(
  cd "${CORE_DIR}"
  cargo build --release -q
)

wait_tcp() {
  local host="$1" port="$2" max="$3"
  local i
  for ((i = 1; i <= max; i++)); do
    if python3 -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('${host}',${port})); s.close()" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

for f in "${KEY_DIR}/p2p_seed.bin" "${KEY_DIR}/p2p_adv.bin" "${KEY_DIR}/p2p_honest.bin"; do
  if [[ ! -f "${f}" ]]; then
    echo "[mesh-test] ERROR: missing key file ${f}" >&2
    exit 1
  fi
done

rm -f "${SEED_LOG}" "${ADV_LOG}" "${HONEST_LOG}" "${DB_PATH}"

free_port() {
  local p="$1" pid
  if command -v lsof >/dev/null 2>&1; then
    for pid in $(lsof -nP -iTCP:"${p}" -sTCP:LISTEN -t 2>/dev/null); do
      kill -9 "${pid}" 2>/dev/null || true
    done
  fi
}
for p in "${SEED_PORT}" "${ADV_PORT}" "${HONEST_PORT}" "${REST_PORT}"; do
  free_port "${p}"
done

ADV_PEER_ID="$(
  cd "${CORE_DIR}" && NEXUS_P2P_KEY_PATH="${KEY_DIR}/p2p_adv.bin" \
    cargo run --release -q -- --print-p2p-peer-id 2>/dev/null | tail -1
)"
if [[ -z "${ADV_PEER_ID}" ]]; then
  echo "[mesh-test] ERROR: could not resolve adversarial PeerId" >&2
  exit 1
fi
echo "[mesh-test] adversarial PeerId=${ADV_PEER_ID}"

cleanup() {
  for pid in "${SEED_PID:-}" "${ADV_PID:-}" "${HONEST_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

echo "[mesh-test] starting SEED (port ${SEED_PORT})..."
(
  cd "${CORE_DIR}"
  export NEXUS_MODE="SEED"
  export NEXUS_SEED_PORT="${SEED_PORT}"
  export NEXUS_SEED_SUBSCRIBE_RESULTS="1"
  export NEXUS_FORCE_EXECUTOR_PEER_ID="${ADV_PEER_ID}"
  export NEXUS_E2EE_ROUTE_RELAX="1"
  export NEXUS_P2P_KEY_PATH="${KEY_DIR}/p2p_seed.bin"
  export NEXUS_NODE_KEY_PATH="${KEY_DIR}/node_key_seed.bin"
  export NEXUS_DB_PATH="${DB_PATH}"
  export NEXUS_ENABLE_REST="0"
  export NEXUS_DISABLE_REPL="1"
  cargo run --release -q
) >"${SEED_LOG}" 2>&1 &
SEED_PID=$!

sleep 4

echo "[mesh-test] starting ADVERSARIAL (listen ${ADV_PORT}; Honest will dial this for gossip mesh)..."
(
  cd "${CORE_DIR}"
  export NEXUS_MODE="CLIENT"
  export NEXUS_SEED_PORT="${SEED_PORT}"
  export NEXUS_CLIENT_LISTEN_PORT="${ADV_PORT}"
  export NEXUS_P2P_KEY_PATH="${KEY_DIR}/p2p_adv.bin"
  export NEXUS_NODE_KEY_PATH="${KEY_DIR}/node_key_adv.bin"
  export NEXUS_DB_PATH="${DB_PATH}"
  export NEXUS_MOCK_INFERENCE="1"
  export NEXUS_ENABLE_REST="0"
  export NEXUS_DISABLE_REPL="1"
  export NEXUS_HOSTED_MODELS="${MODEL_ID}"
  cargo run --release -q -- --adversarial
) >"${ADV_LOG}" 2>&1 &
ADV_PID=$!

echo "[mesh-test] waiting for adversarial TCP/${ADV_PORT}..."
for _ in $(seq 1 60); do
  if grep -q "listening on /ip4/127.0.0.1/tcp/${ADV_PORT}" "${ADV_LOG}" 2>/dev/null; then
    break
  fi
  if ! kill -0 "${ADV_PID}" 2>/dev/null; then
    echo "[mesh-test] ERROR: adversarial exited early; log:" >&2
    tail -40 "${ADV_LOG}" >&2
    exit 1
  fi
  sleep 1
done

echo "[mesh-test] starting HONEST (listen ${HONEST_PORT}, mesh dial adv ${ADV_PORT}, REST ${REST_PORT})..."
(
  cd "${CORE_DIR}"
  export NEXUS_MODE="CLIENT"
  export NEXUS_SEED_PORT="${SEED_PORT}"
  export NEXUS_CLIENT_LISTEN_PORT="${HONEST_PORT}"
  export NEXUS_GOSSIP_MESH_DIAL="/ip4/127.0.0.1/tcp/${ADV_PORT}"
  export NEXUS_P2P_KEY_PATH="${KEY_DIR}/p2p_honest.bin"
  export NEXUS_NODE_KEY_PATH="${KEY_DIR}/node_key_honest.bin"
  export NEXUS_DB_PATH="${DB_PATH}"
  export NEXUS_E2EE="0"
  export NEXUS_MOCK_INFERENCE="1"
  export NEXUS_REST_LISTEN="127.0.0.1:${REST_PORT}"
  export NEXUS_REST_TIMEOUT_SECS="25"
  export NEXUS_API_KEY="${API_KEY}"
  export NEXUS_MODEL_ID="${MODEL_ID}"
  export NEXUS_DISABLE_REPL="1"
  export NEXUS_HOSTED_MODELS="${MODEL_ID}"
  cargo run --release -q
) >"${HONEST_LOG}" 2>&1 &
HONEST_PID=$!

REST_URL="http://127.0.0.1:${REST_PORT}/v1/chat/completions"
echo "[mesh-test] waiting for Honest REST tcp/${REST_PORT}..."
if ! wait_tcp 127.0.0.1 "${REST_PORT}" 120; then
  echo "[mesh-test] ERROR: REST port did not open; honest log:" >&2
  tail -60 "${HONEST_LOG}" >&2
  exit 1
fi

echo "[mesh-test] submitting task via Honest REST (executor forced to adversarial)..."
curl -sS --max-time 35 "${REST_URL}" \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: ${API_KEY}" \
  -d "{
    \"model\": \"${MODEL_ID}\",
    \"messages\": [{\"role\":\"user\",\"content\":\"trigger poison path\"}],
    \"high_priority\": false,
    \"max_tokens\": 8
  }" >/dev/null || true

echo "[mesh-test] waiting for gossip validation on Honest..."
sleep 12

if grep -q "Invalid message received from ${ADV_PEER_ID}" "${HONEST_LOG}"; then
  echo "[mesh-test] OK: Honest log contains Reject WARN for adversarial PeerId"
  grep "Invalid message received from ${ADV_PEER_ID}" "${HONEST_LOG}" | head -3 || true
else
  echo "[mesh-test] FAIL: expected Reject WARN not found in ${HONEST_LOG}" >&2
  echo "--- tail honest log ---" >&2
  tail -80 "${HONEST_LOG}" >&2
  exit 1
fi

cleanup
trap - EXIT
echo "[mesh-test] all processes stopped. Logs: ${SEED_LOG} ${ADV_LOG} ${HONEST_LOG}"
