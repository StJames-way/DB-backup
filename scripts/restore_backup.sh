#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Uso:
  restore_backup.sh TIMESTAMP AGE_IDENTITY PUBLIC_KEY PUBLIC_KEY_SHA256_FILE [OUTPUT_DIR]

Ejemplo:
  ./scripts/restore_backup.sh \
    2026-07-28_02-00-00 \
    /Volumes/Offline/age-identity.txt \
    /Volumes/Offline/backup-signing-public-key.pem \
    /Volumes/Offline/backup-signing-public-key.sha256 \
    "$HOME/restore-2026-07-28"

Este script NO restaura datos en PostgreSQL automáticamente. Verifica, reensambla,
descifra y ejecuta pg_restore --list.
EOF
}

[ "$#" -ge 4 ] && [ "$#" -le 5 ] || { usage >&2; exit 2; }

TIMESTAMP="$1"
AGE_IDENTITY="$2"
PUBLIC_KEY="$3"
PUBLIC_KEY_SHA_FILE="$4"
OUTPUT_DIR="${5:-$PWD/restored-$TIMESTAMP}"
STORAGE_BRANCH="${BACKUP_STORAGE_BRANCH:-backups-signed-latest-30}"

[[ "$TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || {
  echo "Timestamp inválido" >&2; exit 2;
}

for tool in git python3 age pg_restore; do
  command -v "$tool" >/dev/null || { echo "Falta $tool" >&2; exit 1; }
done
for file in "$AGE_IDENTITY" "$PUBLIC_KEY" "$PUBLIC_KEY_SHA_FILE"; do
  [ -r "$file" ] || { echo "No se puede leer: $file" >&2; exit 1; }
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Ejecuta este script dentro del clon de DB-backup" >&2; exit 1;
}
VERIFY="$REPO_ROOT/tools/backup/verify_backup_set.py"
VERIFY_PLAIN="$REPO_ROOT/tools/backup/verify_plaintext_dump.py"
[ -r "$VERIFY" ] && [ -r "$VERIFY_PLAIN" ] || {
  echo "Faltan las herramientas de verificación en main" >&2; exit 1;
}

EXPECTED_KEY_SHA="$(awk 'NF {print $1; exit}' "$PUBLIC_KEY_SHA_FILE")"
[[ "$EXPECTED_KEY_SHA" =~ ^[0-9a-fA-F]{64}$ ]] || {
  echo "El fichero de huella offline no contiene un SHA-256 válido" >&2; exit 1;
}
EXPECTED_KEY_SHA="${EXPECTED_KEY_SHA,,}"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/db-backup-restore.XXXXXX")"
STORAGE_WORKTREE="$WORK_ROOT/storage"

cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "$STORAGE_WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT INT TERM

git -C "$REPO_ROOT" fetch --prune origin "$STORAGE_BRANCH"
git -C "$REPO_ROOT" worktree add --detach "$STORAGE_WORKTREE" "origin/$STORAGE_BRANCH" >/dev/null

MANIFEST_REL="manifests/database_backup_${TIMESTAMP}.json"
MANIFEST="$STORAGE_WORKTREE/$MANIFEST_REL"
[ -f "$MANIFEST" ] || { echo "No existe $MANIFEST_REL en $STORAGE_BRANCH" >&2; exit 1; }

ENCRYPTED="$OUTPUT_DIR/database_backup_${TIMESTAMP}.dump.age"
DUMP="$OUTPUT_DIR/database_backup_${TIMESTAMP}.dump"
CONTENTS="$OUTPUT_DIR/database_backup_${TIMESTAMP}.contents.txt"

python3 "$VERIFY" \
  --repo-root "$STORAGE_WORKTREE" \
  --public-key "$PUBLIC_KEY" \
  --expected-public-key-sha256 "$EXPECTED_KEY_SHA" \
  --manifest "$MANIFEST_REL" \
  --reassemble-to "$ENCRYPTED"

age --decrypt \
  --identity "$AGE_IDENTITY" \
  --output "$DUMP" \
  "$ENCRYPTED"

python3 "$VERIFY_PLAIN" "$MANIFEST" "$DUMP"
pg_restore --list "$DUMP" > "$CONTENTS"
test -s "$CONTENTS"

cat <<EOF
RECUPERACIÓN VERIFICADA

Archivo cifrado: $ENCRYPTED
Dump descifrado: $DUMP
Índice pg_restore: $CONTENTS

Todavía no se ha escrito nada en ninguna base de datos.
Para restaurar en una base vacía, revisa primero el índice y utiliza un comando
pg_restore explícito con la URL de DESTINO, nunca con la URL de producción por error.
EOF
