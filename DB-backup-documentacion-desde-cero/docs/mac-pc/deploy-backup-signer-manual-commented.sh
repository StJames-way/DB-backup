#!/usr/bin/env bash
#
# deploy-backup-signer-manual.sh
#
# Despliega manualmente StJames-way/backup-signer en Fly.io desde este Mac.
#
# MODELO DE SEGURIDAD
# -------------------
# - NO guarda FLY_API_TOKEN en GitHub.
# - NO necesita un workflow de despliegue en GitHub Actions.
# - NO contiene OPENBAO_ROLE_ID ni OPENBAO_SECRET_ID.
# - Usa exclusivamente la sesión local de `flyctl` iniciada con `fly auth login`.
# - Clona el repositorio en un directorio temporal y lo elimina al terminar.
# - Comprueba que el signer autoriza exactamente el SHA indicado del reusable.
# - Comprueba /healthz y /readyz después del despliegue.
#
# IMPORTANTE
# ----------
# Este script despliega `backup-signer`. NO ejecuta el backup de la base de datos.
# El workflow diario de DB-backup sigue funcionando sin ningún token de Fly.io:
#
#   GitHub Actions -> GitHub OIDC -> backup-signer -> AppRole -> OpenBao Transit
#
# PREPARACIÓN, UNA SOLA VEZ
# ------------------------
# 1. Instalar las herramientas necesarias:
#
#      brew install gh flyctl git jq openssl
#
# 2. Autenticarse localmente:
#
#      gh auth login
#      fly auth login
#
# 3. Guardar este archivo en una ruta local:
#
#      mkdir -p "$HOME/.local/bin"
#      install -m 0700 deploy-backup-signer-manual.sh \
#        "$HOME/.local/bin/deploy-backup-signer"
#
# ANTES DE CADA DESPLIEGUE
# -----------------------
# 1. Editar desde GitHub web:
#
#      StJames-way/backup-signer -> fly.toml
#
# 2. Actualizar:
#
#      ALLOWED_JOB_WORKFLOW_REF =
#      "StJames-way/DB-backup/.github/workflows/
#       supabase-age-openbao-reusable.yml@SHA_COMPLETO"
#
#    La línea real debe quedar en una sola línea TOML.
#
# 3. Hacer commit en `main`.
#
# 4. Ejecutar este script pasando el SHA completo:
#
#      "$HOME/.local/bin/deploy-backup-signer" \
#        9df9f393517fffddca9e4bb7264211010cb0912b
#
#    Si no se pasa argumento, utiliza el SHA predeterminado definido más abajo.
#
# QUÉ HACE EL SCRIPT
# ------------------
# 1. Comprueba las sesiones locales de GitHub CLI y Fly CLI.
# 2. Rechaza el uso accidental de FLY_API_TOKEN desde el entorno.
# 3. Clona backup-signer en un directorio temporal.
# 4. Comprueba los archivos obligatorios.
# 5. Comprueba el SHA autorizado y la configuración de OpenBao.
# 6. Busca claves privadas que no deberían estar en el repositorio.
# 7. Verifica el certificado público de la CA.
# 8. Comprueba la sintaxis Python.
# 9. Valida fly.toml.
# 10. Ejecuta `fly deploy --remote-only`.
# 11. Comprueba /healthz y /readyz.
# 12. Elimina automáticamente el clon temporal.
#

set -Eeuo pipefail

# Aplicación Fly que se despliega.
APP="camino-backup-signer"

# Repositorio GitHub que contiene el signer.
REPOSITORY="StJames-way/backup-signer"

# SHA del reusable de DB-backup autorizado por el signer.
#
# Es preferible pasarlo como primer argumento para que el despliegue sea
# deliberado y visible:
#
#   ./deploy-backup-signer-manual.sh <SHA_DE_40_CARACTERES>
#
# El valor siguiente se utiliza únicamente cuando no se pasa argumento.
DEFAULT_REUSABLE_SHA="9df9f393517fffddca9e4bb7264211010cb0912b"

EXPECTED_REUSABLE_SHA="${1:-$DEFAULT_REUSABLE_SHA}"
EXPECTED_REUSABLE_REF=\
"StJames-way/DB-backup/.github/workflows/supabase-age-openbao-reusable.yml@${EXPECTED_REUSABLE_SHA}"


# Muestra un error y detiene inmediatamente el despliegue.
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}


# ---------------------------------------------------------------------------
# PASO 1: validar el argumento SHA
# ---------------------------------------------------------------------------

[[ "$EXPECTED_REUSABLE_SHA" =~ ^[0-9a-f]{40}$ ]] || \
  die "el SHA esperado debe tener 40 caracteres hexadecimales en minúsculas"


# ---------------------------------------------------------------------------
# PASO 2: impedir que se use por accidente un token Fly inyectado
# ---------------------------------------------------------------------------
#
# Queremos que `flyctl` use la sesión local creada con `fly auth login`.
# Si FLY_API_TOKEN estuviera definido, podría sustituir esa sesión local.

if [[ -n "${FLY_API_TOKEN:-}" ]]; then
  die \
    "FLY_API_TOKEN está definido en el entorno. Ejecuta: unset FLY_API_TOKEN"
fi


# ---------------------------------------------------------------------------
# PASO 3: comprobar herramientas locales
# ---------------------------------------------------------------------------

for tool in gh fly git curl jq openssl python3; do
  command -v "$tool" >/dev/null 2>&1 || \
    die "falta el comando obligatorio: $tool"
done


# ---------------------------------------------------------------------------
# PASO 4: comprobar autenticación local
# ---------------------------------------------------------------------------

printf 'Comprobando la sesión local de GitHub CLI...\n'

gh auth status >/dev/null 2>&1 || \
  die "GitHub CLI no está autenticado; ejecuta: gh auth login"

printf 'Comprobando la sesión local de Fly CLI...\n'

fly auth whoami >/dev/null 2>&1 || \
  die "Fly CLI no está autenticado; ejecuta: fly auth login"


# ---------------------------------------------------------------------------
# PASO 5: crear un directorio temporal seguro
# ---------------------------------------------------------------------------

WORKDIR="$(
  mktemp -d "${TMPDIR:-/tmp}/backup-signer-deploy.XXXXXX"
)"

# Este archivo guarda temporalmente resultados de la búsqueda de claves.
PRIVATE_KEY_FINDINGS="$WORKDIR/private-key-findings.txt"


# El directorio temporal se elimina tanto si el despliegue termina bien
# como si falla o se interrumpe con Ctrl+C.
cleanup() {
  rm -rf "$WORKDIR"
}

trap cleanup EXIT INT TERM


# ---------------------------------------------------------------------------
# PASO 6: clonar el repositorio desde GitHub
# ---------------------------------------------------------------------------

printf 'Clonando %s en un directorio temporal...\n' "$REPOSITORY"

gh repo clone \
  "$REPOSITORY" \
  "$WORKDIR/repository" \
  -- \
  --depth=1

cd "$WORKDIR/repository"

test -z "$(git status --porcelain)" || \
  die "el clon temporal no está limpio"

DEPLOY_COMMIT="$(git rev-parse HEAD)"

printf 'Commit de backup-signer que se desplegará: %s\n' \
  "$DEPLOY_COMMIT"


# ---------------------------------------------------------------------------
# PASO 7: comprobar los archivos obligatorios
# ---------------------------------------------------------------------------

printf 'Comprobando archivos obligatorios...\n'

for file in \
  Dockerfile \
  fly.toml \
  pyproject.toml \
  app/config.py \
  app/main.py \
  app/openbao.py \
  certs/camino-openbao-ca.pem
do
  test -s "$file" || \
    die "falta el archivo obligatorio o está vacío: $file"
done


# ---------------------------------------------------------------------------
# PASO 8: validar fly.toml y el SHA autorizado
# ---------------------------------------------------------------------------
#
# Esta comprobación evita desplegar un signer que acepte un reusable antiguo,
# otro repositorio o una ruta OpenBao incorrecta.

printf 'Comprobando allowlist y configuración OpenBao...\n'

python3 - "$EXPECTED_REUSABLE_REF" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

expected_reusable_ref = sys.argv[1]
text = Path("fly.toml").read_text(encoding="utf-8")


def read_toml_string(name: str) -> str:
    pattern = rf'(?m)^\s*{re.escape(name)}\s*=\s*"([^"]+)"\s*$'
    match = re.search(pattern, text)

    if match is None:
        raise SystemExit(f"ERROR: falta {name} en fly.toml")

    return match.group(1)


actual_reusable_ref = read_toml_string("ALLOWED_JOB_WORKFLOW_REF")

if actual_reusable_ref != expected_reusable_ref:
    raise SystemExit(
        "ERROR: ALLOWED_JOB_WORKFLOW_REF no coincide.\n"
        f"Esperado: {expected_reusable_ref}\n"
        f"Actual:   {actual_reusable_ref}"
    )


required_values = {
    "ALLOWED_CALLER_WORKFLOW_REF": (
        "StJames-way/DB-backup/.github/workflows/"
        "supabase-backup-dispatch.yml@refs/heads/main"
    ),
    "OPENBAO_ADDR": "https://camino-openbao.internal:8200",
    "OPENBAO_CA_FILE": "/etc/ssl/certs/camino-openbao-ca.pem",
    "OPENBAO_AUTH_MOUNT": "approle-backup",
    "OPENBAO_TRANSIT_MOUNT": "transit-backup",
    "OPENBAO_KEY_NAME": "supabase-backup-manifest",
}


for name, expected_value in required_values.items():
    actual_value = read_toml_string(name)

    if actual_value != expected_value:
        raise SystemExit(
            f"ERROR: {name} no coincide.\n"
            f"Esperado: {expected_value}\n"
            f"Actual:   {actual_value}"
        )


print("OK: allowlist y conexión OpenBao verificadas")
PY


# ---------------------------------------------------------------------------
# PASO 9: comprobar que se despliega la versión nueva de app/main.py
# ---------------------------------------------------------------------------

grep -Fq '@app.get("/readyz")' app/main.py || \
  die "app/main.py no contiene el endpoint /readyz"


# ---------------------------------------------------------------------------
# PASO 10: impedir que una clave privada llegue a la imagen
# ---------------------------------------------------------------------------
#
# camino-openbao-ca.pem es un certificado público y puede estar en GitHub.
# No debe existir ningún bloque PRIVATE KEY en el repositorio.

if grep -RIl \
  --exclude-dir=.git \
  --exclude='*.pyc' \
  -E 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' \
  . >"$PRIVATE_KEY_FINDINGS" 2>/dev/null
then
  cat "$PRIVATE_KEY_FINDINGS" >&2
  die "se encontró una posible clave privada en el repositorio"
fi


# ---------------------------------------------------------------------------
# PASO 11: validar la CA pública incluida en la imagen
# ---------------------------------------------------------------------------

printf 'Comprobando el certificado público de la CA OpenBao...\n'

openssl x509 \
  -in certs/camino-openbao-ca.pem \
  -noout \
  -subject \
  -issuer \
  -dates


# ---------------------------------------------------------------------------
# PASO 12: comprobar sintaxis Python
# ---------------------------------------------------------------------------

printf 'Comprobando la sintaxis Python...\n'

python3 -m py_compile \
  app/config.py \
  app/main.py \
  app/openbao.py


# ---------------------------------------------------------------------------
# PASO 13: validar la configuración Fly
# ---------------------------------------------------------------------------

printf 'Validando fly.toml...\n'

fly config validate \
  --app "$APP" \
  --config fly.toml


# ---------------------------------------------------------------------------
# PASO 14: desplegar manualmente desde el Mac
# ---------------------------------------------------------------------------
#
# --remote-only construye la imagen en Fly.
# La autenticación procede de `fly auth login` en este Mac.
# No se usa ningún token almacenado en GitHub Actions.

printf '\nDesplegando manualmente desde este Mac...\n'
printf 'No se utiliza ningún FLY_API_TOKEN de GitHub Actions.\n'

fly deploy \
  --remote-only \
  --app "$APP" \
  --config fly.toml


# ---------------------------------------------------------------------------
# Función auxiliar: esperar a que un endpoint devuelva el estado esperado
# ---------------------------------------------------------------------------

check_endpoint() {
  local path="$1"
  local expected_status="$2"
  local response_file

  response_file="$(mktemp "$WORKDIR/response.XXXXXX")"

  # 30 intentos x 5 segundos = hasta 150 segundos.
  for attempt in $(seq 1 30); do
    printf 'Intento %s/30 para %s...\n' "$attempt" "$path"

    if curl \
      --fail \
      --silent \
      --show-error \
      --output "$response_file" \
      "https://${APP}.fly.dev${path}"
    then
      if jq -e \
        --arg expected "$expected_status" \
        '.status == $expected' \
        "$response_file" >/dev/null
      then
        cat "$response_file"
        printf '\n'
        return 0
      fi
    fi

    sleep 5
  done

  printf 'Última respuesta recibida de %s:\n' "$path" >&2
  cat "$response_file" >&2 2>/dev/null || true
  printf '\n' >&2

  return 1
}


# ---------------------------------------------------------------------------
# PASO 15: comprobar liveness
# ---------------------------------------------------------------------------

printf '\nComprobando /healthz...\n'

check_endpoint "/healthz" "ok" || \
  die "/healthz no alcanzó el estado esperado"


# ---------------------------------------------------------------------------
# PASO 16: comprobar conexión TLS con OpenBao
# ---------------------------------------------------------------------------
#
# /readyz comprueba:
# - que la CA está instalada;
# - que el hostname del certificado es válido;
# - que camino-openbao.internal resuelve;
# - que OpenBao responde;
# - que OpenBao está inicializado y desprecintado.
#
# No consume un token AppRole.

printf '\nComprobando /readyz...\n'

check_endpoint "/readyz" "ready" || \
  die "/readyz no alcanzó el estado esperado"


# ---------------------------------------------------------------------------
# PASO 17: mostrar la release resultante
# ---------------------------------------------------------------------------

printf '\nÚltima release registrada en Fly:\n'

fly releases \
  --app "$APP" |
head -n 4


# ---------------------------------------------------------------------------
# RESULTADO
# ---------------------------------------------------------------------------

printf '\nOK: backup-signer desplegado manualmente desde este Mac.\n'
printf 'Commit de backup-signer desplegado: %s\n' "$DEPLOY_COMMIT"
printf 'SHA reusable autorizado: %s\n' "$EXPECTED_REUSABLE_SHA"

printf '\nSiguiente paso:\n'
printf '%s\n' \
  'Ejecuta el workflow manual de StJames-way/DB-backup y comprueba la firma.'
