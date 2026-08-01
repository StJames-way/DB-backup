#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"

[ -n "$TARGET" ] || {
  echo "Uso: install-docs-into-repo.sh /ruta/al/DB-backup" >&2
  exit 1
}

[ -d "$TARGET/.git" ] || {
  echo "ERROR: $TARGET no parece un repositorio Git" >&2
  exit 1
}

[ -f "$TARGET/.github/workflows/supabase-backup-dispatch.yml" ] || {
  echo "ERROR: no parece el repositorio DB-backup" >&2
  exit 1
}

mkdir -p "$TARGET/docs"
cp -R "$SOURCE_DIR/docs/." "$TARGET/docs/"

printf 'OK: documentación copiada a %s/docs\n' "$TARGET"
printf 'Revisa con: git -C %q status --short\n' "$TARGET"
