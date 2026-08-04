#!/usr/bin/env bash
set -euo pipefail

APP="${SIGNER_APP:-camino-backup-signer}"
GATEWAY="${GATEWAY_URL:-https://camino-backup-gateway.santiago-way.workers.dev}"
TOKEN_FILE="${HEALTH_TOKEN_FILE:-/tmp/backup-health-token}"

[ -s "$TOKEN_FILE" ] || { echo "Falta $TOKEN_FILE" >&2; exit 2; }

CONFIG="$(fly config show -a "$APP")"
grep -q 'min_machines_running = 0' <<<"$CONFIG" || { echo 'min_machines_running no es 0' >&2; exit 1; }
grep -q 'auto_start_machines = true' <<<"$CONFIG" || { echo 'auto_start_machines no está activo' >&2; exit 1; }

fly machine list -a "$APP"

CODE="$(curl -sS --max-time 30 -o /tmp/readyz.json -w '%{http_code}'   -H "Authorization: Bearer $(cat "$TOKEN_FILE")" "$GATEWAY/readyz")"
cat /tmp/readyz.json
echo
[ "$CODE" = 200 ] || { echo "readyz devolvió $CODE" >&2; exit 1; }

echo 'OK: gateway -> VPC -> Tunnel -> Flycast -> signer -> OpenBao'
