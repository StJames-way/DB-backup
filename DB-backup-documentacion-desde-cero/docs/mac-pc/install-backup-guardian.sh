#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] || {
  echo "ERROR: ejecuta este script dentro del repositorio DB-backup" >&2
  exit 1
}

SOURCE="$ROOT/docs/mac-pc/backup-guardian-v4.yml"
TARGET="$ROOT/.github/workflows/backup-guardian.yml"

[ -f "$SOURCE" ] || {
  echo "ERROR: falta $SOURCE" >&2
  exit 1
}

mkdir -p "$(dirname "$TARGET")"
install -m 0644 "$SOURCE" "$TARGET"

git -C "$ROOT" diff --check
printf 'OK: Guardian instalado en %s\n' "$TARGET"
printf 'Ahora revisa: git diff -- %s\n' "$TARGET"
