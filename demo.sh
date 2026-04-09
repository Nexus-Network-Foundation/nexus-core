#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="${ROOT_DIR}/scripts/bootstrap.sh"

if [[ ! -x "${BOOTSTRAP}" ]]; then
  echo "[demo] ERROR: missing executable bootstrap script at ${BOOTSTRAP}" >&2
  echo "[demo] Hint: run: chmod +x scripts/bootstrap.sh" >&2
  exit 1
fi

exec "${BOOTSTRAP}"

