#!/usr/bin/env bash
set -euo pipefail

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
  echo "Uso: $0 /ruta/backup.dump [salida-toc.txt]" >&2
  exit 2
}

DUMP="$1"
TOC="${2:-${DUMP}.contents.txt}"
test -s "$DUMP" || { echo "El dump no existe o está vacío: $DUMP" >&2; exit 1; }

choose_pg_restore() {
  local candidate
  if [ -n "${PG_RESTORE_BIN:-}" ]; then
    printf '%s\n' "$PG_RESTORE_BIN"
    return
  fi
  for candidate in \
    "$(command -v pg_restore 2>/dev/null || true)" \
    /opt/homebrew/opt/postgresql@17/bin/pg_restore \
    /usr/local/opt/postgresql@17/bin/pg_restore \
    /usr/lib/postgresql/17/bin/pg_restore; do
    [ -n "$candidate" ] && [ -x "$candidate" ] || continue
    if "$candidate" --version | grep -Eq 'PostgreSQL\) (17|18)\.'; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  return 1
}

PG_RESTORE="$(choose_pg_restore)" || {
  echo "Necesitas pg_restore 17 o posterior. En macOS: brew install postgresql@17" >&2
  exit 1
}

"$PG_RESTORE" --version
"$PG_RESTORE" --list "$DUMP" > "$TOC"
test -s "$TOC"

required=(
  public.pois
  public.pois_final
  public.pois_import
  public.legendary_pois
  public.pois_backup_before_fountain_dedupe
  public.legendary_poi_source_links
  public.stage_elevation_profiles
  public.poi_restaurant_details
  public.poi_tourism_details
  public.safety_zones
  public.mobility_pois
  auth.users
  storage.objects
)

missing=0
for qualified in "${required[@]}"; do
  schema="${qualified%%.*}"
  table="${qualified#*.}"
  if grep -Eq " TABLE DATA ${schema} ${table} " "$TOC"; then
    echo "OK: $qualified"
  else
    echo "FALTA: $qualified" >&2
    missing=1
  fi
done

printf 'Entradas TABLE DATA: '
grep -c ' TABLE DATA ' "$TOC" || true
[ "$missing" -eq 0 ] || exit 1
echo "TOC guardado en: $TOC"
