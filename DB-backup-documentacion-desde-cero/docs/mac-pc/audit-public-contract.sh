#!/usr/bin/env bash
set -Eeuo pipefail

REPO="StJames-way/DB-backup"
EXPECTED_REUSABLE_SHA="9df9f393517fffddca9e4bb7264211010cb0912b"
EXPECTED_AGE_SHA="f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa"
EXPECTED_KEY_SHA="4011dd69e227bfcf6f39b3f44b1ad499d2a582c9f3eed93d8896e61b7485ce96"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || {
  echo "ERROR: ejecuta dentro de DB-backup" >&2
  exit 1
}

failures=0
check_equal() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'OK: %s
' "$label"
  else
    printf 'ERROR: %s
  actual:   %s
  esperado: %s
'       "$label" "$actual" "$expected" >&2
    failures=$((failures + 1))
  fi
}

RECIPIENT="$(tr -d '\r\n' < "$ROOT/config/age-recipient.txt")"
if command -v sha256sum >/dev/null 2>&1; then
  AGE_SHA="$(printf '%s' "$RECIPIENT" | sha256sum | awk '{print $1}')"
  KEY_SHA="$(openssl pkey -pubin -in "$ROOT/config/backup-signing-public-key.pem" -outform DER | sha256sum | awk '{print $1}')"
else
  AGE_SHA="$(printf '%s' "$RECIPIENT" | shasum -a 256 | awk '{print $1}')"
  KEY_SHA="$(openssl pkey -pubin -in "$ROOT/config/backup-signing-public-key.pem" -outform DER | shasum -a 256 | awk '{print $1}')"
fi

CALLER_SHA="$(
  sed -nE     's#.*supabase-age-openbao-reusable\.yml@([0-9a-f]{40}).*#\1#p'     "$ROOT/.github/workflows/supabase-backup-dispatch.yml" |
  head -n 1
)"

check_equal 'huella recipient age' "$AGE_SHA" "$EXPECTED_AGE_SHA"
check_equal 'huella clave pública Ed25519' "$KEY_SHA" "$EXPECTED_KEY_SHA"
check_equal 'SHA reusable del caller' "$CALLER_SHA" "$EXPECTED_REUSABLE_SHA"

for pair in   "BACKUP_AGE_RECIPIENT|age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae"   "BACKUP_SIGNER_URL|https://camino-backup-signer.fly.dev"   "BACKUP_FORMAT_VERSION|5"   "BACKUP_STORAGE_BRANCH|backups-signed-latest-30"
do
  name="${pair%%|*}"
  expected="${pair#*|}"
  actual="$(gh variable get "$name" --repo "$REPO" 2>/dev/null || true)"
  check_equal "GitHub variable $name" "$actual" "$expected"
done

if [ "$failures" -ne 0 ]; then
  echo "AUDITORÍA: ERROR ($failures diferencias)" >&2
  exit 1
fi

echo 'AUDITORÍA PÚBLICA: CORRECTA'
