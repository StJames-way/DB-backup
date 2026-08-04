#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Este instalador automático está preparado para Homebrew." >&2
  echo "En Linux/WSL instala los paquetes equivalentes." >&2
  exit 2
fi

brew install age gh flyctl jq openssl@3 postgresql@17 supabase/tap/supabase node

for tool in age age-keygen gh fly jq openssl pg_dump pg_restore psql supabase node npm; do
  command -v "$tool" >/dev/null || { echo "Falta $tool" >&2; exit 1; }
done

echo "Herramientas instaladas. Ejecuta gh auth login, fly auth login y supabase login."
