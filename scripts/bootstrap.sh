#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${ROOT_DIR}/nexus-core"

SEED_LOG="${ROOT_DIR}/seed.log"
CLIENT_LOG="${ROOT_DIR}/client.log"

API_KEY="${NEXUS_API_KEY:-steve-secret-key}"
MODEL_ID="${NEXUS_MODEL_ID:-nexus-infer-v1}"
REST_LISTEN="${NEXUS_REST_LISTEN:-127.0.0.1:8080}"
REST_TIMEOUT_SECS="${NEXUS_REST_TIMEOUT_SECS:-300}"
VERIFICATION_RATE="${NEXUS_VERIFICATION_RATE:-1.0}"

CARGO_BIN="${CARGO_BIN:-$HOME/.cargo/bin/cargo}"

need_cmd() {
  local c="$1"
  if ! command -v "${c}" >/dev/null 2>&1; then
    echo "[bootstrap] ERROR: missing dependency: ${c}" >&2
    return 1
  fi
}

need_file() {
  local p="$1"
  if [[ ! -f "${p}" ]]; then
    echo "[bootstrap] ERROR: missing file: ${p}" >&2
    return 1
  fi
}

wait_for_rest() {
  local url="$1"
  local max_secs="$2"
  for _ in $(seq 1 "${max_secs}"); do
    if curl -sS -o /dev/null -m 1 "${url}" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

cleanup() {
  if [[ -n "${SEED_PID:-}" ]] && kill -0 "${SEED_PID}" 2>/dev/null; then
    kill "${SEED_PID}" 2>/dev/null || true
  fi
  if [[ -n "${CLIENT_PID:-}" ]] && kill -0 "${CLIENT_PID}" 2>/dev/null; then
    kill "${CLIENT_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

need_cmd curl
need_cmd jq

if [[ ! -x "${CARGO_BIN}" ]]; then
  echo "[bootstrap] ERROR: cargo not found at ${CARGO_BIN}" >&2
  echo "[bootstrap] Hint: set CARGO_BIN=/path/to/cargo" >&2
  exit 1
fi

need_file "${CORE_DIR}/Cargo.toml"

echo "[bootstrap] model_id=${MODEL_ID}"
echo "[bootstrap] rest_listen=${REST_LISTEN}"

echo "[bootstrap] starting SEED in background..."
(
  cd "${CORE_DIR}"
  export NEXUS_MODE="SEED"
  export NEXUS_DB_PATH="${ROOT_DIR}/nexus.db"
  export NEXUS_MODEL_ID="${MODEL_ID}"
  "${CARGO_BIN}" run --quiet
) >"${SEED_LOG}" 2>&1 &
SEED_PID=$!

echo "[bootstrap] seed pid=${SEED_PID} log=${SEED_LOG}"
echo "[bootstrap] waiting 10s for seed warmup..."
sleep 10

echo "[bootstrap] starting CLIENT in background (REST enabled)..."
(
  cd "${CORE_DIR}"
  export NEXUS_MODE="CLIENT"
  export NEXUS_DB_PATH="${ROOT_DIR}/nexus.db"
  export NEXUS_API_KEY="${API_KEY}"
  export NEXUS_MODEL_ID="${MODEL_ID}"
  export NEXUS_VERIFICATION_RATE="${VERIFICATION_RATE}"
  export NEXUS_REST_LISTEN="${REST_LISTEN}"
  export NEXUS_REST_TIMEOUT_SECS="${REST_TIMEOUT_SECS}"
  "${CARGO_BIN}" run --quiet
) >"${CLIENT_LOG}" 2>&1 &
CLIENT_PID=$!

echo "[bootstrap] client pid=${CLIENT_PID} log=${CLIENT_LOG}"

REST_URL="http://${REST_LISTEN}/v1/chat/completions"
echo "[bootstrap] waiting for REST to come up: ${REST_URL}"
if ! wait_for_rest "${REST_URL}" 60; then
  echo "[bootstrap] ERROR: REST did not come up within 60s" >&2
  echo "[bootstrap] logs: ${SEED_LOG} ${CLIENT_LOG}" >&2
  exit 1
fi

echo "[bootstrap] calling REST API..."
RESP="$(
  curl -sS "${REST_URL}" \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: ${API_KEY}" \
    -d "{
      \"model\": \"${MODEL_ID}\",
      \"messages\": [{\"role\":\"user\",\"content\":\"Say hello in one sentence.\"}],
      \"high_priority\": true,
      \"max_tokens\": 32
    }"
)"

echo "${RESP}"

CONTENT="$(echo "${RESP}" | jq -r '.choices[0].message.content // empty')"
STATUS="$(echo "${RESP}" | jq -r '.metadata.verification_status // empty')"

if [[ -z "${CONTENT}" ]]; then
  echo "[bootstrap] ERROR: response missing choices[0].message.content" >&2
  exit 1
fi
if [[ "${CONTENT}" == *"ModelNotFound"* ]]; then
  echo "[bootstrap] ERROR: ModelNotFound returned (check NEXUS_MODEL_ID / model routing)" >&2
  exit 1
fi
if [[ "${STATUS}" != "verified" ]]; then
  echo "[bootstrap] ERROR: verification_status != verified (got='${STATUS}')" >&2
  exit 1
fi

echo
echo "[bootstrap] OK: content is non-ModelNotFound and verification_status=verified"
echo "[bootstrap] logs: ${SEED_LOG} ${CLIENT_LOG}"

