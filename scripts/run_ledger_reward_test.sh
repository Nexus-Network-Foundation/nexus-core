#!/usr/bin/env bash
set -euo pipefail
set +m

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${ROOT_DIR}/nexus-core"
KEY_DIR="${ROOT_DIR}/.test_ncu_telemetry"

SEED_PORT="${NEXUS_SEED_PORT:-50431}"
HONEST_PORT="${NEXUS_HONEST_PORT:-50434}"

SEED_LOG="${ROOT_DIR}/.test_ledger_seed.log"
HONEST_LOG="${ROOT_DIR}/.test_ledger_honest.log"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ledger-test] ERROR: missing: $1" >&2
    exit 1
  }
}

need_cmd cargo
need_cmd python3
need_cmd lsof
need_cmd grep

for f in "${KEY_DIR}/p2p_seed.bin" "${KEY_DIR}/node_key_seed.bin" "${KEY_DIR}/p2p_honest.bin" "${KEY_DIR}/node_key_honest.bin"; do
  if [[ ! -f "${f}" ]]; then
    echo "[ledger-test] ERROR: missing key file ${f}" >&2
    echo "[ledger-test] Hint: run scripts/run_telemetry_ncu_test.sh once to populate ${KEY_DIR}" >&2
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

echo "[ledger-test] building release..."
( cd "${CORE_DIR}" && cargo build --release -q )

cleanup() {
  for pid in "${SEED_PID:-}" "${HONEST_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

echo "[ledger-test] starting Node A (Seed) tcp/${SEED_PORT}..."
(
  cd "${CORE_DIR}"
  export NEXUS_MODE="SEED"
  export NEXUS_SEED_PORT="${SEED_PORT}"
  export NEXUS_ENABLE_REST="0"
  export NEXUS_DISABLE_REPL="1"
  export NEXUS_MOCK_INFERENCE="1"
  export NEXUS_TELEMETRY_INTERVAL_MIN_SECS="1"
  export NEXUS_TELEMETRY_INTERVAL_MAX_SECS="1"
  export NEXUS_P2P_KEY_PATH="${KEY_DIR}/p2p_seed.bin"
  export NEXUS_NODE_KEY_PATH="${KEY_DIR}/node_key_seed.bin"
  cargo run --release -q
) >"${SEED_LOG}" 2>&1 &
SEED_PID=$!

sleep 3

echo "[ledger-test] starting Node B (Honest) tcp/${HONEST_PORT}..."
(
  cd "${CORE_DIR}"
  export NEXUS_MODE="CLIENT"
  export NEXUS_SEED_PORT="${SEED_PORT}"
  export NEXUS_CLIENT_LISTEN_PORT="${HONEST_PORT}"
  export NEXUS_ENABLE_REST="0"
  export NEXUS_DISABLE_REPL="1"
  export NEXUS_MOCK_INFERENCE="1"
  export NEXUS_TELEMETRY_INTERVAL_MIN_SECS="1"
  export NEXUS_TELEMETRY_INTERVAL_MAX_SECS="1"
  export NEXUS_P2P_KEY_PATH="${KEY_DIR}/p2p_honest.bin"
  export NEXUS_NODE_KEY_PATH="${KEY_DIR}/node_key_honest.bin"
  cargo run --release -q
) >"${HONEST_LOG}" 2>&1 &
HONEST_PID=$!

echo "[ledger-test] flooding telemetry (1s interval) and monitoring rewards for ~8s..."
deadline=$((SECONDS + 12))
count=0
last_line=""

while [[ ${SECONDS} -lt ${deadline} ]]; do
  if [[ -f "${HONEST_LOG}" ]]; then
    # Count rewards; also keep the last matching line for display.
    c="$(grep -c "\\[ledger\\] 💰 Reward earned!" "${HONEST_LOG}" 2>/dev/null || true)"
    if [[ "${c}" -gt "${count}" ]]; then
      count="${c}"
      last_line="$(grep "\\[ledger\\] 💰 Reward earned!" "${HONEST_LOG}" | tail -1 || true)"
      if [[ "${count}" -ge 3 ]]; then
        break
      fi
    fi
  fi
  sleep 1
done

if [[ "${count}" -lt 3 ]]; then
  echo "[ledger-test] FAIL: expected >=3 reward logs within timeout; got=${count}" >&2
  echo "--- tail honest ---" >&2
  tail -120 "${HONEST_LOG}" >&2 || true
  echo "--- tail seed ---" >&2
  tail -120 "${SEED_LOG}" >&2 || true
  exit 1
fi

echo
echo "[ledger-test] SUCCESS: reward logs observed (count=${count})"
printf '\033[1;33m%s\033[0m\n' "${last_line}"
echo

cleanup
trap - EXIT
echo "[ledger-test] all processes stopped."
exit 0

