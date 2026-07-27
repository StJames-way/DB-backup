#!/usr/bin/env bash
# Restaura un backup PostgreSQL dividido y cifrado con age.
# Uso: ./restore_age_backup_complete.sh [CARPETA_BACKUP] [CARPETA_SALIDA] [MANIFEST]

set -Eeuo pipefail
umask 077

BACKUP_DIR="${1:-.}"
OUTPUT_DIR="${2:-$BACKUP_DIR}"
MANIFEST_ARG="${3:-}"

TMP_IDENTITY=""
TMP_AGE=""
TMP_DUMP=""
TMP_CONTENTS=""

cleanup() {
  local code=$?
  [ -n "${TMP_IDENTITY:-}" ] && rm -f "$TMP_IDENTITY"
  [ -n "${TMP_AGE:-}" ] && rm -f "$TMP_AGE"
  [ -n "${TMP_DUMP:-}" ] && rm -f "$TMP_DUMP"
  [ -n "${TMP_CONTENTS:-}" ] && rm -f "$TMP_CONTENTS"
  exit "$code"
}
trap cleanup EXIT INT TERM

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '\n==> %s\n' "$*"
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "Falta el comando requerido: $1"
}

expand_path() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

file_size() {
  if stat -f '%z' "$1" >/dev/null 2>&1; then
    stat -f '%z' "$1"
  else
    stat -c '%s' "$1"
  fi
}

resolve_part() {
  local recorded="$1"
  local candidate

  candidate="$BACKUP_DIR/$recorded"
  [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }

  candidate="$BACKUP_DIR/$(basename "$recorded")"
  [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }

  candidate="$(dirname "$MANIFEST_FILE")/../$recorded"
  [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }

  return 1
}

need age
need age-keygen
need jq
need pg_restore
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  die "Falta sha256sum o shasum."
fi

BACKUP_DIR="$(expand_path "$BACKUP_DIR")"
OUTPUT_DIR="$(expand_path "$OUTPUT_DIR")"
[ -d "$BACKUP_DIR" ] || die "No existe la carpeta: $BACKUP_DIR"
mkdir -p "$OUTPUT_DIR"
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd -P)"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"

info "Localizando el manifest"
if [ -n "$MANIFEST_ARG" ]; then
  MANIFEST_ARG="$(expand_path "$MANIFEST_ARG")"
  if [ -f "$MANIFEST_ARG" ]; then
    MANIFEST_FILE="$MANIFEST_ARG"
  elif [ -f "$BACKUP_DIR/$MANIFEST_ARG" ]; then
    MANIFEST_FILE="$BACKUP_DIR/$MANIFEST_ARG"
  elif [ -f "$BACKUP_DIR/manifests/$MANIFEST_ARG" ]; then
    MANIFEST_FILE="$BACKUP_DIR/manifests/$MANIFEST_ARG"
  else
    die "No se encontró el manifest indicado: $MANIFEST_ARG"
  fi
else
  MANIFEST_FILE="$(
    find "$BACKUP_DIR" -maxdepth 2 -type f -name 'database_backup_*.json' -print |
      sort |
      tail -1
  )"
fi

[ -n "${MANIFEST_FILE:-}" ] && [ -s "$MANIFEST_FILE" ] || die "No se encontró ningún manifest."
jq -e . "$MANIFEST_FILE" >/dev/null || die "El manifest no contiene JSON válido."

PART_COUNT="$(jq -r '.part_count // 0' "$MANIFEST_FILE")"
JSON_PART_COUNT="$(jq '.parts | if type == "array" then length else 0 end' "$MANIFEST_FILE")"
ENCRYPTED_NAME="$(jq -r '.encrypted_original_filename // empty' "$MANIFEST_FILE")"
EXPECTED_GLOBAL_SHA="$(jq -r '.encrypted_sha256 // empty' "$MANIFEST_FILE")"
EXPECTED_RECIPIENT_SHA="$(jq -r '.encryption.recipient_sha256 // empty' "$MANIFEST_FILE")"

[ "$JSON_PART_COUNT" -gt 0 ] || die "El manifest no contiene partes válidas."
[ "$PART_COUNT" -eq "$JSON_PART_COUNT" ] || die "part_count no coincide con la lista de partes."
[ -n "$ENCRYPTED_NAME" ] || die "Falta encrypted_original_filename en el manifest."
[ -n "$EXPECTED_GLOBAL_SHA" ] || die "Falta encrypted_sha256 en el manifest."

printf 'Manifest:        %s\n' "$MANIFEST_FILE"
printf 'Número de partes: %s\n' "$PART_COUNT"

AGE_BASENAME="$(basename "$ENCRYPTED_NAME")"
AGE_FILE="$OUTPUT_DIR/$AGE_BASENAME"
TMP_AGE="$OUTPUT_DIR/.${AGE_BASENAME}.reassembling.$$"
: > "$TMP_AGE"

info "Verificando y uniendo las partes"
VERIFIED=0
while IFS= read -r entry; do
  RECORDED_NAME="$(jq -r '.name // empty' <<<"$entry")"
  EXPECTED_SIZE="$(jq -r '.size_bytes // empty' <<<"$entry")"
  EXPECTED_PART_SHA="$(jq -r '.sha256 // empty' <<<"$entry")"

  [ -n "$RECORDED_NAME" ] || die "Una parte no tiene nombre."
  PART_FILE="$(resolve_part "$RECORDED_NAME")" || die "Falta la parte: $RECORDED_NAME"

  ACTUAL_SIZE="$(file_size "$PART_FILE")"
  [ "$ACTUAL_SIZE" = "$EXPECTED_SIZE" ] || die "Tamaño incorrecto: $(basename "$PART_FILE")"

  ACTUAL_PART_SHA="$(sha256_file "$PART_FILE")"
  [ "$ACTUAL_PART_SHA" = "$EXPECTED_PART_SHA" ] || die "SHA-256 incorrecto: $(basename "$PART_FILE")"

  cat "$PART_FILE" >> "$TMP_AGE"
  VERIFIED=$((VERIFIED + 1))
  printf 'OK  %s  (%s bytes)\n' "$(basename "$PART_FILE")" "$ACTUAL_SIZE"
done < <(jq -c '.parts[]' "$MANIFEST_FILE")

[ "$VERIFIED" -eq "$PART_COUNT" ] || die "Se verificaron $VERIFIED partes; se esperaban $PART_COUNT."
[ -s "$TMP_AGE" ] || die "El archivo recompuesto está vacío."

ACTUAL_GLOBAL_SHA="$(sha256_file "$TMP_AGE")"
[ "$ACTUAL_GLOBAL_SHA" = "$EXPECTED_GLOBAL_SHA" ] || die "El SHA-256 global no coincide."

mv -f "$TMP_AGE" "$AGE_FILE"
TMP_AGE=""
printf 'OK: archivo age recompuesto: %s\n' "$AGE_FILE"

info "Solicitando la identidad privada age"
printf 'Ruta del archivo de identidad (Enter para pegar AGE-SECRET-KEY-1...): '
IFS= read -r IDENTITY_INPUT

if [ -n "$IDENTITY_INPUT" ]; then
  IDENTITY_FILE="$(expand_path "$IDENTITY_INPUT")"
  [ -s "$IDENTITY_FILE" ] || die "La identidad no existe o está vacía: $IDENTITY_FILE"
  chmod 600 "$IDENTITY_FILE" 2>/dev/null || true
else
  printf 'Clave privada age (no se mostrará): '
  IFS= read -r -s PRIVATE_KEY
  printf '\n'
  case "$PRIVATE_KEY" in
    AGE-SECRET-KEY-1*) ;;
    *) die "La clave no empieza por AGE-SECRET-KEY-1." ;;
  esac
  TMP_IDENTITY="$(mktemp "${TMPDIR:-/tmp}/age-identity.XXXXXX")"
  chmod 600 "$TMP_IDENTITY"
  printf '%s\n' "$PRIVATE_KEY" > "$TMP_IDENTITY"
  unset PRIVATE_KEY
  IDENTITY_FILE="$TMP_IDENTITY"
fi

DERIVED_RECIPIENT="$(age-keygen -y "$IDENTITY_FILE" 2>/dev/null)" || die "Identidad age inválida."
printf 'Recipient derivado: %s\n' "$DERIVED_RECIPIENT"

if [ -n "$EXPECTED_RECIPIENT_SHA" ] && [ "$EXPECTED_RECIPIENT_SHA" != "null" ]; then
  ACTUAL_RECIPIENT_SHA="$(sha256_text "$DERIVED_RECIPIENT")"
  [ "$ACTUAL_RECIPIENT_SHA" = "$EXPECTED_RECIPIENT_SHA" ] || die "La identidad no corresponde al recipient usado en este backup."
  printf 'OK: la identidad coincide con el manifest.\n'
else
  printf 'AVISO: el manifest no contiene recipient_sha256; se probará el descifrado directamente.\n'
fi

if [[ "$AGE_BASENAME" == *.dump.age ]]; then
  RESTORED_BASENAME="${AGE_BASENAME%.dump.age}.restored.dump"
else
  RESTORED_BASENAME="${AGE_BASENAME%.age}.restored"
fi

RESTORED_DUMP="$OUTPUT_DIR/$RESTORED_BASENAME"
CONTENTS_FILE="${RESTORED_DUMP}.contents.txt"
TMP_DUMP="$OUTPUT_DIR/.${RESTORED_BASENAME}.decrypting.$$"
TMP_CONTENTS="$OUTPUT_DIR/.${RESTORED_BASENAME}.contents.$$"

info "Descifrando el backup"
rm -f "$TMP_DUMP" "$TMP_CONTENTS"
age --decrypt --identity "$IDENTITY_FILE" --output "$TMP_DUMP" "$AGE_FILE" || die "age no pudo descifrar el backup."
[ -s "$TMP_DUMP" ] || die "El dump descifrado está vacío."
chmod 600 "$TMP_DUMP"

info "Validando el dump PostgreSQL"
pg_restore --list "$TMP_DUMP" > "$TMP_CONTENTS" || die "pg_restore no reconoce el dump descifrado."
[ -s "$TMP_CONTENTS" ] || die "pg_restore no produjo un listado de contenido."

mv -f "$TMP_DUMP" "$RESTORED_DUMP"
TMP_DUMP=""
mv -f "$TMP_CONTENTS" "$CONTENTS_FILE"
TMP_CONTENTS=""
chmod 600 "$RESTORED_DUMP" "$CONTENTS_FILE"

info "RESTAURACIÓN VERIFICADA"
printf 'Archivo cifrado:    %s\n' "$AGE_FILE"
printf 'Dump descifrado:    %s\n' "$RESTORED_DUMP"
printf 'Listado pg_restore: %s\n' "$CONTENTS_FILE"
printf 'Tamaño del dump:    %s bytes\n' "$(file_size "$RESTORED_DUMP")"
printf '\nPrimeras entradas del dump:\n'
head -20 "$CONTENTS_FILE"
printf '\nOK: backup recompuesto, verificado, descifrado y validado sin errores.\n'
