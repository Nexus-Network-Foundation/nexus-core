#!/usr/bin/env bash
set -euo pipefail
set +m

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${ROOT_DIR}/nexus-core"
KEY_SRC="${ROOT_DIR}/.test_pqc_queue"
KEY_DIR="${ROOT_DIR}/.test_identity_ban"

HONEST_PORT="50001"
ADV_PORT="50002"

HONEST_LOG="${ROOT_DIR}/.test_identity_honest.log"
ADV_LOG="${ROOT_DIR}/.test_identity_adv.log"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[identity-test] ERROR: missing: $1" >&2
    exit 1
  }
}

need_cmd cargo
need_cmd python3
need_cmd lsof
need_cmd grep

mkdir -p "${KEY_DIR}"

for f in p2p_seed.bin node_key_seed.bin p2p_adv.bin node_key_adv.bin; do
  if [[ ! -f "${KEY_DIR}/${f}" ]]; then
    if [[ ! -f "${KEY_SRC}/${f}" ]]; then
      echo "[identity-test] ERROR: missing ${KEY_SRC}/${f} (run poison mesh test once to generate keys)" >&2
      exit 1
    fi
    cp "${KEY_SRC}/${f}" "${KEY_DIR}/${f}"
  fi
done

free_port() {
  local p="$1" pid
  for pid in $(lsof -nP -iTCP:"${p}" -sTCP:LISTEN -t 2>/dev/null); do
    kill -9 "${pid}" 2>/dev/null || true
  done
}

rm -f "${HONEST_LOG}" "${ADV_LOG}"
free_port "${HONEST_PORT}"
free_port "${ADV_PORT}"

echo "[identity-test] building release..."
( cd "${CORE_DIR}" && cargo build --release -q )

cleanup() {
  for pid in "${HONEST_PID:-}" "${ADV_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

echo "[identity-test] starting Node A (Honest) listening tcp/${HONEST_PORT}..."
(
  cd "${CORE_DIR}"
  cargo run --release -q -- \
    --mode seed \
    --port "${HONEST_PORT}" \
    --rest=false \
    --mock-inference \
    --p2p-key-path "${KEY_DIR}/p2p_seed.bin" \
    --node-key-path "${KEY_DIR}/node_key_seed.bin"
) >"${HONEST_LOG}" 2>&1 &
HONEST_PID=$!

sleep 3

echo "[identity-test] starting Node B (Adversarial) dialing Node A with bad handshake..."
(
  cd "${CORE_DIR}"
  cargo run --release -q -- \
    --mode client \
    --port "${ADV_PORT}" \
    --rest=false \
    --mock-inference \
    --bad-handshake \
    --p2p-key-path "${KEY_DIR}/p2p_adv.bin" \
    --node-key-path "${KEY_DIR}/node_key_adv.bin"
) >"${ADV_LOG}" 2>&1 &
ADV_PID=$!

echo "[identity-test] waiting for Honest ban log..."
deadline=$((SECONDS + 20))
hit=""
while [[ ${SECONDS} -lt ${deadline} ]]; do
  hit="$(grep -m 1 "\\[identity\\] ⚠️ PQC Handshake failed! Disconnecting malicious peer:" "${HONEST_LOG}" 2>/dev/null || true)"
  if [[ -n "${hit}" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "${hit}" ]]; then
  echo "[identity-test] FAIL: did not observe ban log within timeout" >&2
  echo "--- tail honest ---" >&2
  tail -120 "${HONEST_LOG}" >&2 || true
  echo "--- tail adversarial ---" >&2
  tail -120 "${ADV_LOG}" >&2 || true
  exit 1
fi

echo
echo "[identity-test] SUCCESS: malicious peer was disconnected"
printf '\033[1;31m%s\033[0m\n' "${hit}"
echo

cleanup
trap - EXIT
echo "[identity-test] all processes stopped."
exit 0

