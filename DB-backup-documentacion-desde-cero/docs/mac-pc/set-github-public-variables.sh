#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-StJames-way/DB-backup}"
read -r -p 'Recipient age público: ' AGE_RECIPIENT
read -r -p 'URL HTTPS del Cloudflare gateway: ' GATEWAY_URL

[[ "$AGE_RECIPIENT" =~ ^age1[0-9a-z]+$ ]] || { echo 'Recipient inválido' >&2; exit 2; }
[[ "$GATEWAY_URL" == https://* ]] || { echo 'Gateway debe usar HTTPS' >&2; exit 2; }

gh variable set BACKUP_AGE_RECIPIENT --repo "$REPO" --body "$AGE_RECIPIENT"
gh variable set BACKUP_SIGNER_URL --repo "$REPO" --body "${GATEWAY_URL%/}"

echo "Variables actualizadas. No se modificó SUPABASE_DB_URL."
