#!/usr/bin/env bash
set -euo pipefail

APP="${SIGNER_APP:-camino-backup-signer}"
ROOT="${SIGNER_REPO:-$PWD}"
cd "$ROOT"

grep -Eq 'min_machines_running[[:space:]]*=[[:space:]]*0' fly.toml || {
  echo 'Se exige min_machines_running = 0' >&2
  exit 1
}

fly config validate
fly deploy -a "$APP"
fly status -a "$APP"

echo 'Despliegue terminado. Ejecuta verify-backup-signer-deployment-macos-v3.sh.'
