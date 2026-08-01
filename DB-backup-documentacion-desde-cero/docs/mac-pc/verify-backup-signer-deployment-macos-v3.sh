#!/usr/bin/env bash
#
# verify-backup-signer-deployment.sh
#
# Verifica el despliegue de camino-backup-signer sin mostrar ningún secreto.
# Compatible con el Bash 3.2 incluido por defecto en macOS.
# Selecciona la release con el número de versión más alto, no el último
# elemento devuelto por la API de Fly.
#
# Uso:
#
#   chmod 700 verify-backup-signer-deployment.sh
#
#   ./verify-backup-signer-deployment.sh \
#     9df9f393517fffddca9e4bb7264211010cb0912b
#
# Este script comprueba:
# - sesión local de Fly y GitHub;
# - que la última release de Fly está completa;
# - que los únicos secretos Fly son OPENBAO_ROLE_ID y OPENBAO_SECRET_ID;
# - que ambos secretos están desplegados en todas las Machines;
# - que /healthz responde "ok";
# - que /readyz responde "ready";
# - que la Machine tiene las variables necesarias sin imprimir secretos;
# - que no hay tokens/root secrets impropios en el entorno de la aplicación;
# - que la CA pública existe y puede cargarse;
# - que Uvicorn se ejecuta como UID 10001;
# - que ALLOWED_JOB_WORKFLOW_REF contiene exactamente el SHA indicado;
# - que /v1/sign rechaza una petición sin OIDC.
#
# El script NO solicita una firma real. La prueba criptográfica completa se
# realiza después ejecutando el workflow de DB-backup desde GitHub Actions.

set -Eeuo pipefail

APP="camino-backup-signer"
REPOSITORY="StJames-way/backup-signer"
EXPECTED_SHA="${1:-}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]] || \
  die "pasa como primer argumento el SHA reusable completo de 40 caracteres"

EXPECTED_JOB_WORKFLOW_REF="StJames-way/DB-backup/.github/workflows/supabase-age-openbao-reusable.yml@${EXPECTED_SHA}"

for tool in fly gh curl jq python3 awk grep sort; do
  command -v "$tool" >/dev/null 2>&1 || die "falta el comando: $tool"
done

printf '\n[1/9] Comprobando autenticación local...\n'
fly auth whoami >/dev/null 2>&1 || die "ejecuta: fly auth login"
gh auth status >/dev/null 2>&1 || die "ejecuta: gh auth login"

printf '\n[2/9] Confirmando que GitHub no conserva FLY_API_TOKEN...\n'
if gh secret list --repo "$REPOSITORY" 2>/dev/null |
   awk '{print $1}' |
   grep -Fxq 'FLY_API_TOKEN'
then
  die "FLY_API_TOKEN todavía existe como secret de GitHub"
fi
printf 'OK: GitHub no contiene FLY_API_TOKEN.\n'

printf '\n[3/9] Estado y última release de Fly...\n'
fly status --app "$APP"
printf '\n'
fly releases --app "$APP" | head -n 5

LATEST_RELEASE_STATUS="$(
  fly releases --app "$APP" --json |
  jq -r '
    if type == "array" and length > 0 then
      (
        max_by(
          (
            .Version
            // .version
            // .ID
            // .id
            // 0
          )
          | tostring
          | sub("^v"; "")
          | tonumber
        )
        | (.Status // .status // "")
      )
    elif type == "object" then
      (.Status // .status // "")
    else
      ""
    end
  '
)"

# Compatible con Bash 3.2, que es la versión incluida por defecto en macOS.
# No usamos ${VARIABLE,,}, porque esa conversión a minúsculas requiere Bash 4+.
case "$LATEST_RELEASE_STATUS" in
  complete|Complete|COMPLETE)
    ;;
  *)
    die "la última release no figura como complete: ${LATEST_RELEASE_STATUS:-desconocido}"
    ;;
esac

printf 'OK: última release completa.\n'

printf '\n[4/9] Comprobando los secretos Fly sin mostrar sus valores...\n'
fly secrets list --app "$APP"

fly secrets list --app "$APP" --json |
python3 -c '
from __future__ import annotations

import json
import sys

data = json.load(sys.stdin)

if isinstance(data, dict):
    for key in ("secrets", "Secrets", "items", "Items"):
        candidate = data.get(key)
        if isinstance(candidate, list):
            data = candidate
            break
    else:
        data = [data]

if not isinstance(data, list):
    raise SystemExit("ERROR: formato JSON inesperado de fly secrets list")

rows = []

for item in data:
    if not isinstance(item, dict):
        continue

    name = next(
        (
            str(item[key])
            for key in ("Name", "name", "NAME")
            if item.get(key) is not None
        ),
        "",
    )
    status = next(
        (
            str(item[key])
            for key in ("Status", "status", "STATUS")
            if item.get(key) is not None
        ),
        "",
    )

    if name:
        rows.append((name, status))

actual_names = sorted(name for name, _ in rows)
expected_names = sorted(("OPENBAO_ROLE_ID", "OPENBAO_SECRET_ID"))

if actual_names != expected_names:
    raise SystemExit(
        "ERROR: la lista de Fly Secrets no coincide.\n"
        f"Esperados: {expected_names}\n"
        f"Actuales:  {actual_names}"
    )

for name, status in rows:
    if status.lower() != "deployed":
        raise SystemExit(
            f"ERROR: {name} no está Deployed; estado={status!r}"
        )

print("OK: existen exactamente los dos secretos AppRole y están Deployed.")
'


printf '\n[5/9] Comprobando health checks registrados por Fly...\n'
fly checks list --app "$APP" || die "falló fly checks list"

printf '\n[6/9] Comprobando /healthz...\n'
HEALTH_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    --retry 5 \
    --retry-connrefused \
    --retry-delay 2 \
    "https://${APP}.fly.dev/healthz"
)"
printf '%s\n' "$HEALTH_JSON"
jq -e '.status == "ok"' <<<"$HEALTH_JSON" >/dev/null || \
  die "/healthz no devolvió status=ok"

printf '\n[7/9] Comprobando /readyz y la conexión con OpenBao...\n'
READY_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    --retry 5 \
    --retry-connrefused \
    --retry-delay 2 \
    "https://${APP}.fly.dev/readyz"
)"
printf '%s\n' "$READY_JSON"
jq -e '.status == "ready"' <<<"$READY_JSON" >/dev/null || \
  die "/readyz no devolvió status=ready"

printf '\n[8/9] Verificando el entorno dentro de la Machine sin mostrar secretos...\n'

EXPECTED_REF_JSON="$(
  python3 -c \
    'import json, sys; print(json.dumps(sys.argv[1]))' \
    "$EXPECTED_JOB_WORKFLOW_REF"
)"

REMOTE_PYTHON="$(
cat <<PY
from __future__ import annotations

import os
import pathlib
import re
import ssl

expected_job_workflow_ref = ${EXPECTED_REF_JSON}

required_secret_names = (
    "OPENBAO_ROLE_ID",
    "OPENBAO_SECRET_ID",
)

missing_secrets = [
    name for name in required_secret_names
    if not os.environ.get(name)
]
if missing_secrets:
    raise SystemExit(
        "ERROR: faltan secretos requeridos: "
        + ", ".join(missing_secrets)
    )

forbidden_names = (
    "FLY_API_TOKEN",
    "BAO_TOKEN",
    "VAULT_TOKEN",
    "OPENBAO_ROOT_TOKEN",
    "SUPABASE_DB_URL",
    "BACKUP_ENCRYPTION_PASSWORD",
    "AGE_SECRET_KEY",
    "AGE_PRIVATE_KEY",
)

present_forbidden = [
    name for name in forbidden_names
    if os.environ.get(name)
]
if present_forbidden:
    raise SystemExit(
        "ERROR: variables prohibidas presentes: "
        + ", ".join(present_forbidden)
    )

required_values = {
    "GITHUB_OIDC_ISSUER": (
        "https://token.actions.githubusercontent.com"
    ),
    "GITHUB_OIDC_AUDIENCE": (
        "openbao://supabase-backup-signing"
    ),
    "ALLOWED_REPOSITORY": "StJames-way/DB-backup",
    "ALLOWED_REF": "refs/heads/main",
    "ALLOWED_JOB_WORKFLOW_REF": expected_job_workflow_ref,
    "ALLOWED_CALLER_WORKFLOW_REF": (
        "StJames-way/DB-backup/.github/workflows/"
        "supabase-backup-dispatch.yml@refs/heads/main"
    ),
    "OPENBAO_ADDR": "https://camino-openbao.internal:8200",
    "OPENBAO_CA_FILE": (
        "/etc/ssl/certs/camino-openbao-ca.pem"
    ),
    "OPENBAO_AUTH_MOUNT": "approle-backup",
    "OPENBAO_TRANSIT_MOUNT": "transit-backup",
    "OPENBAO_KEY_NAME": "supabase-backup-manifest",
}

for name, expected in required_values.items():
    actual = os.environ.get(name)
    if actual != expected:
        raise SystemExit(
            f"ERROR: {name} no coincide. "
            f"Esperado={expected!r}; actual={actual!r}"
        )

for numeric_name in (
    "ALLOWED_REPOSITORY_ID",
    "ALLOWED_REPOSITORY_OWNER_ID",
):
    value = os.environ.get(numeric_name, "")
    if re.fullmatch(r"[1-9][0-9]*", value) is None:
        raise SystemExit(
            f"ERROR: {numeric_name} no es un ID numérico válido"
        )

ca_path = pathlib.Path(
    os.environ["OPENBAO_CA_FILE"]
)
if not ca_path.is_file() or ca_path.stat().st_size == 0:
    raise SystemExit("ERROR: falta la CA pública de OpenBao")

ca_text = ca_path.read_text(encoding="utf-8")
if "BEGIN PRIVATE KEY" in ca_text:
    raise SystemExit("ERROR: la ruta de CA contiene una clave privada")
if "BEGIN CERTIFICATE" not in ca_text:
    raise SystemExit("ERROR: la ruta de CA no contiene un certificado")

ssl.create_default_context(cafile=str(ca_path))

uvicorn_uids = []
for cmdline_path in pathlib.Path("/proc").glob("[0-9]*/cmdline"):
    try:
        cmdline = cmdline_path.read_bytes().replace(b"\x00", b" ")
        if b"uvicorn" not in cmdline:
            continue

        status_path = cmdline_path.parent / "status"
        for line in status_path.read_text(
            encoding="utf-8",
            errors="replace",
        ).splitlines():
            if line.startswith("Uid:"):
                uvicorn_uids.append(int(line.split()[1]))
                break
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        continue

if not uvicorn_uids:
    raise SystemExit("ERROR: no se encontró el proceso Uvicorn")

if any(uid != 10001 for uid in uvicorn_uids):
    raise SystemExit(
        "ERROR: Uvicorn no se ejecuta exclusivamente como UID 10001"
    )

print("OK: los dos secretos AppRole están presentes y no se mostraron.")
print("OK: no hay tokens administrativos ni claves privadas en el entorno.")
print("OK: allowlist, OpenBao y CA tienen los valores esperados.")
print("OK: Uvicorn se ejecuta como UID 10001.")
PY
)"

REMOTE_B64="$(
  printf '%s' "$REMOTE_PYTHON" |
  python3 -c \
    'import base64, sys; print(base64.b64encode(sys.stdin.buffer.read()).decode())'
)"

REMOTE_COMMAND="python -c \"import base64;exec(compile(base64.b64decode('${REMOTE_B64}'),'<deployment-check>','exec'))\""

fly ssh console \
  --app "$APP" \
  --command "$REMOTE_COMMAND"

printf '\n[9/9] Confirmando que /v1/sign no acepta peticiones sin GitHub OIDC...\n'
UNAUTH_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --data '{"manifest":{}}' \
    "https://${APP}.fly.dev/v1/sign"
)"

[[ "$UNAUTH_STATUS" == "401" ]] || \
  die "se esperaba HTTP 401 sin OIDC y se recibió $UNAUTH_STATUS"

printf 'OK: /v1/sign exige autenticación OIDC.\n'

printf '\n============================================================\n'
printf 'VERIFICACIÓN DEL DESPLIEGUE: CORRECTA\n'
printf '============================================================\n'
printf 'Aplicación: %s\n' "$APP"
printf 'Reusable autorizado: %s\n' "$EXPECTED_SHA"
printf '\nFalta únicamente la prueba criptográfica extremo a extremo:\n'
printf '%s\n' \
  'ejecutar DB-backup y confirmar POST /v1/sign = 200 y firma Ed25519 válida.'
