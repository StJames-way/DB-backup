#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$(pwd)}"
mkdir -p "$TARGET/.github/workflows"
install -m 0644 "$ROOT/backup-guardian-v4.yml" \
  "$TARGET/.github/workflows/backup-guardian.yml"
echo 'Guardian instalado. Revisa el diff y crea MR.'
