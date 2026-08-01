#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/bin"

mkdir -p "$DEST"

install -m 0700 "$SCRIPT_DIR/deploy-backup-signer-manual-commented.sh" \
  "$DEST/deploy-backup-signer"
install -m 0700 "$SCRIPT_DIR/verify-backup-signer-deployment-macos-v3.sh" \
  "$DEST/verify-backup-signer-deployment"
install -m 0700 "$SCRIPT_DIR/deploy-backup-signer-and-verify.sh" \
  "$DEST/deploy-backup-signer-and-verify"
install -m 0700 "$SCRIPT_DIR/test-supabase-backup-e2e-v2.sh" \
  "$DEST/test-supabase-backup-e2e"

for script in \
  "$DEST/deploy-backup-signer" \
  "$DEST/verify-backup-signer-deployment" \
  "$DEST/deploy-backup-signer-and-verify" \
  "$DEST/test-supabase-backup-e2e"
do
  bash -n "$script"
  printf 'OK: %s\n' "$script"
done
