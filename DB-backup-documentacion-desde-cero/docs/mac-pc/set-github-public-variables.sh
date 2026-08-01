#!/usr/bin/env bash
set -Eeuo pipefail

REPO="StJames-way/DB-backup"

gh auth status >/dev/null 2>&1 || {
  echo "ERROR: ejecuta gh auth login" >&2
  exit 1
}

set_var() {
  local name="$1"
  local value="$2"
  gh variable set "$name" --repo "$REPO" --body "$value"
  printf 'OK: %s
' "$name"
}

set_var BACKUP_AGE_RECIPIENT 'age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae'
set_var BACKUP_ALLOWED_REF 'refs/heads/main'
set_var BACKUP_DISPATCH_SOURCE 'supabase-edge-function'
set_var BACKUP_FORMAT_VERSION '5'
set_var BACKUP_PART_SIZE_BYTES '94371840'
set_var BACKUP_POLICY 'daily_full_age_encrypted_openbao_signed_retain_last_30_verified'
set_var BACKUP_RETENTION_COUNT '30'
set_var BACKUP_SIGNER_URL 'https://camino-backup-signer.fly.dev'
set_var BACKUP_SIGNING_PUBLIC_KEY_SHA256 '4011dd69e227bfcf6f39b3f44b1ad499d2a582c9f3eed93d8896e61b7485ce96'
set_var BACKUP_STORAGE_BRANCH 'backups-signed-latest-30'
set_var BACKUP_TIMEOUT_MINUTES '120'
set_var BACKUP_TIMEZONE 'Europe/Madrid'
set_var EXPECTED_AGE_RECIPIENT_SHA256 'f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa'
set_var OPENBAO_OIDC_AUDIENCE 'openbao://supabase-backup-signing'

printf '
IMPORTANTE: solo BACKUP_AGE_RECIPIENT y BACKUP_SIGNER_URL son leídas
'
printf 'directamente por el workflow actual. Las demás son copias del contrato.
'
