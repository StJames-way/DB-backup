#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Uso:
  BACKUP_STORAGE_BRANCH='rama' ./scripts/restore_backup.sh \
    TIMESTAMP \
    /ruta/age-identity.txt \
    /ruta/backup-signing-public-key.pem \
    /ruta/backup-signing-public-key.sha256 \
    /directorio/salida
EOF
}

[ "$#" -eq 5 ] || { usage; exit 2; }

TIMESTAMP="$1"
AGE_IDENTITY="$2"
PUBLIC_KEY="$3"
PUBLIC_KEY_SHA_FILE="$4"
OUTPUT_DIR="$5"
: "${BACKUP_STORAGE_BRANCH:?Define BACKUP_STORAGE_BRANCH}"

[[ "$TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || {
  echo "Timestamp inválido" >&2; exit 1;
}
for path in "$AGE_IDENTITY" "$PUBLIC_KEY" "$PUBLIC_KEY_SHA_FILE"; do
  test -f "$path" || { echo "Falta $path" >&2; exit 1; }
done
for tool in age git pg_restore python3; do
  command -v "$tool" >/dev/null || { echo "Falta $tool" >&2; exit 1; }
done
python3 -c 'import cryptography' >/dev/null 2>&1 || {
  echo "Falta cryptography; instala tools/backup/requirements.txt" >&2; exit 1;
}

git rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "Ejecuta este script dentro del clon de DB-backup" >&2; exit 1;
}
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

git fetch origin "$BACKUP_STORAGE_BRANCH"
git worktree remove --force "$OUTPUT_DIR/repository" >/dev/null 2>&1 || true
mkdir -p "$OUTPUT_DIR"
git worktree add --detach "$OUTPUT_DIR/repository" "origin/$BACKUP_STORAGE_BRANCH"

EXPECTED_KEY_SHA="$(awk 'NF {print tolower($1); exit}' "$PUBLIC_KEY_SHA_FILE")"
[[ "$EXPECTED_KEY_SHA" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Huella offline inválida" >&2; exit 1;
}

MANIFEST="$OUTPUT_DIR/repository/manifests/database_backup_${TIMESTAMP}.json"
ENCRYPTED="$OUTPUT_DIR/database_backup_${TIMESTAMP}.dump.age"
DUMP="$OUTPUT_DIR/database_backup_${TIMESTAMP}.dump"
CONTENTS="$OUTPUT_DIR/database_backup_${TIMESTAMP}.contents.txt"

test -f "$MANIFEST" || { echo "No existe $MANIFEST" >&2; exit 1; }

python3 tools/backup/verify_backup_set.py \
  --repo-root "$OUTPUT_DIR/repository" \
  --public-key "$PUBLIC_KEY" \
  --expected-public-key-sha256 "$EXPECTED_KEY_SHA" \
  --manifest "$MANIFEST" \
  --reassemble-to "$ENCRYPTED"

age --decrypt \
  --identity "$AGE_IDENTITY" \
  --output "$DUMP" \
  "$ENCRYPTED"

python3 tools/backup/verify_plaintext_dump.py "$MANIFEST" "$DUMP"
pg_restore --list "$DUMP" > "$CONTENTS"

echo "RECUPERACIÓN VERIFICADA"
echo "Dump: $DUMP"
echo "Contenido: $CONTENTS"
