#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

EXPECTED_REUSABLE='9c1562857b371396e478fe078dd1ace772a93abc'
EXPECTED_AGE='f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa'
EXPECTED_SIGNING='4011dd69e227bfcf6f39b3f44b1ad499d2a582c9f3eed93d8896e61b7485ce96'
EXPECTED_CA='807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa'
EXPECTED_GATEWAY='b8863d62b3e1202b604de3b499b9e4e99751259c68e4a706b72c0a98e6c35553'

fail() { echo "ERROR: $*" >&2; exit 1; }

DISPATCH_SHA="$(sed -nE 's#.*supabase-age-openbao-reusable.yml@([0-9a-f]{40}).*#\1#p'   .github/workflows/supabase-backup-dispatch.yml | head -n1)"
[ "$DISPATCH_SHA" = "$EXPECTED_REUSABLE" ] || fail "SHA dispatcher desalineado: $DISPATCH_SHA"

AGE_VALUE="$(tr -d '\r\n' < config/age-recipient.txt)"
AGE_ACTUAL="$(printf '%s' "$AGE_VALUE" | sha256sum | awk '{print $1}')"
[ "$AGE_ACTUAL" = "$EXPECTED_AGE" ] || fail "recipient age desalineado"

SIGN_ACTUAL="$(openssl pkey -pubin -in config/backup-signing-public-key.pem -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
[ "$SIGN_ACTUAL" = "$EXPECTED_SIGNING" ] || fail "clave pública desalineada"

CA_ACTUAL="$(openssl x509 -in config/prod-ca-2021.crt -outform DER | sha256sum | awk '{print $1}')"
[ "$CA_ACTUAL" = "$EXPECTED_CA" ] || fail "CA Supabase desalineada"

grep -q "$EXPECTED_GATEWAY" .github/workflows/supabase-age-openbao-reusable.yml || fail "falta gateway SHA"
! grep -R --line-number -E 'uses:.*@(main|master)$' .github/workflows || fail "workflow móvil detectado"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  URL="$(gh variable get BACKUP_SIGNER_URL --repo StJames-way/DB-backup)"
  URL_SHA="$(printf '%s' "${URL%/}" | sha256sum | awk '{print $1}')"
  [ "$URL_SHA" = "$EXPECTED_GATEWAY" ] || fail "BACKUP_SIGNER_URL desalineada"
fi

echo "OK: contrato público alineado"
