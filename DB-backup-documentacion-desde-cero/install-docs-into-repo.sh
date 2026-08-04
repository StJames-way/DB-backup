#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "Uso: $0 /ruta/a/DB-backup" >&2; exit 2; }
[ -d "$TARGET" ] || { echo "No existe: $TARGET" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 0644 "$ROOT/GUIA_BACKUP_DESDE_CERO.md" \
  "$TARGET/docs/GUIA_BACKUP_DESDE_CERO.md"

rsync -av "$ROOT/docs/" "$TARGET/DB-backup-documentacion-desde-cero/docs/"
install -m 0644 "$ROOT/README.md" \
  "$TARGET/DB-backup-documentacion-desde-cero/README.md"
install -m 0644 "$ROOT/GUIA_BACKUP_DESDE_CERO.md" \
  "$TARGET/DB-backup-documentacion-desde-cero/GUIA_BACKUP_DESDE_CERO.md"

echo "Documentación instalada. Revisa git diff antes de commit."
