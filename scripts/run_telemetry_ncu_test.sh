#!/usr/bin/env bash
set -euo pipefail
set +m

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${ROOT_DIR}/nexus-core"
KEY_DIR="${ROOT_DIR}/.test_ncu_telemetry"

SEED_PORT="${NEXUS_SEED_PORT:-50331}"
HONEST_PORT="${NEXUS_HONEST_PORT:-50334}"

SEED_LOG="${ROOT_DIR}/.test_ncu_seed.log"
HONEST_LOG="${ROOT_DIR}/.test_ncu_honest.log"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ncu-test] ERROR: missing: $1" >&2
    exit 1
  }
}

need_cmd cargo
need_cmd python3
need_cmd lsof

mkdir -p "${KEY_DIR}"
if [[ ! -f "${KEY_DIR}/p2p_seed.bin" ]]; then
  # Reuse the repo's existing deterministic test keys.
  if [[ -f "${ROOT_DIR}/.test_pqc_queue/p2p_seed.bin" ]]; then
    cp "${ROOT_DIR}/.test_pqc_queue/p2p_seed.bin" "${KEY_DIR}/p2p_seed.bin"
    cp "${ROOT_DIR}/.test_pqc_queue/node_key_seed.bin" "${KEY_DIR}/node_key_seed.bin"
    cp "${ROOT_DIR}/.test_pqc_queue/p2p_honest.bin" "${KEY_DIR}/p2p_honest.bin"
    cp "${ROOT_DIR}/.test_pqc_queue/node_key_honest.bin" "${KEY_DIR}/node_key_honest.bin"
  fi
fi

for f in "${KEY_DIR}/p2p_seed.bin" "${KEY_DIR}/node_key_seed.bin" "${KEY_DIR}/p2p_honest.bin" "${KEY_DIR}/node_key_honest.bin"; do
  if [[ ! -f "${f}" ]]; then
    echo "[ncu-test] ERROR: missing key file ${f}" >&2
    echo "[ncu-test] Hint: run scripts/run_poison_mesh_honest_reject.sh once, or place keys under ${KEY_DIR}" >&2
    exit 1
  fi
done

free_port() {
  local p="$1" pid
  for pid in $(lsof -nP -iTCP:"${p}" -sTCP:LISTEN -t 2>/dev/null); do
    kill -9 "${pid}" 2>/dev/null || true
  done
}

rm -f "${SEED_LOG}" "${HONEST_LOG}"
free_port "${SEED_PORT}"
free_port "${HONEST_PORT}"

echo "[ncu-test] ensuring release binary is built..."
( cd "${CORE_DIR}" && cargo build --release -q )

cleanup() {
  for pid in "${SEED_PID:-}" "${HONEST_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

echo "[ncu-test] starting Node A (Seed) on tcp/${SEED_PORT}..."
(
  cd "${CORE_DIR}"
  export NEXUS_MODE="SEED"
  export NEXUS_SEED_PORT="${SEED_PORT}"
  export NEXUS_ENABLE_REST="0"
  export NEXUS_DISABLE_REPL="1"
  export NEXUS_MOCK_INFERENCE="1"
  export NEXUS_P2P_KEY_PATH="${KEY_DIR}/p2p_seed.bin"
  export NEXUS_NODE_KEY_PATH="${KEY_DIR}/node_key_seed.bin"
  cargo run --release -q
) >"${SEED_LOG}" 2>&1 &
SEED_PID=$!

sleep 3

echo "[ncu-test] starting Node B (Honest) on tcp/${HONEST_PORT}..."
(
  cd "${CORE_DIR}"
  export NEXUS_MODE="CLIENT"
  export NEXUS_SEED_PORT="${SEED_PORT}"
  export NEXUS_CLIENT_LISTEN_PORT="${HONEST_PORT}"
  export NEXUS_ENABLE_REST="0"
  export NEXUS_DISABLE_REPL="1"
  export NEXUS_MOCK_INFERENCE="1"
  export NEXUS_P2P_KEY_PATH="${KEY_DIR}/p2p_honest.bin"
  export NEXUS_NODE_KEY_PATH="${KEY_DIR}/node_key_honest.bin"
  cargo run --release -q
) >"${HONEST_LOG}" 2>&1 &
HONEST_PID=$!

echo "[ncu-test] waiting ~30s for telemetry exchange (publish interval 10-20s)..."

deadline=$((SECONDS + 35))
found_line=""
found_file=""

while [[ ${SECONDS} -lt ${deadline} ]]; do
  if [[ -f "${SEED_LOG}" ]]; then
    found_line="$(grep -m 1 "\\[telemetry\\] Received NCU declaration from" "${SEED_LOG}" || true)"
    if [[ -n "${found_line}" ]]; then
      found_file="${SEED_LOG}"
      break
    fi
  fi
  if [[ -f "${HONEST_LOG}" ]]; then
    found_line="$(grep -m 1 "\\[telemetry\\] Received NCU declaration from" "${HONEST_LOG}" || true)"
    if [[ -n "${found_line}" ]]; then
      found_file="${HONEST_LOG}"
      break
    fi
  fi
  sleep 1
done

if [[ -z "${found_line}" ]]; then
  echo "[ncu-test] FAIL: telemetry log not detected within 35s" >&2
  echo "--- tail seed ---" >&2
  tail -80 "${SEED_LOG}" >&2 || true
  echo "--- tail honest ---" >&2
  tail -80 "${HONEST_LOG}" >&2 || true
  exit 1
fi

echo
echo "[ncu-test] SUCCESS: detected telemetry acceptance via async validation queue"
echo "[ncu-test] source log: ${found_file}"
echo
printf '\033[1;32m%s\033[0m\n' "${found_line}"
echo

cleanup
trap - EXIT
echo "[ncu-test] all processes stopped."
exit 0
