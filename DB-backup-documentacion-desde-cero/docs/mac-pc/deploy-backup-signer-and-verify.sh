#!/usr/bin/env bash
#
# Despliega manualmente backup-signer y, solo después de un despliegue correcto,
# ejecuta el Backup Guardian de DB-backup y espera su canario de producción.
#
# No almacena FLY_API_TOKEN ni PAT en GitHub.
# Usa la sesión local de flyctl y gh.
#
# Uso:
#   deploy-backup-signer-and-verify <SHA_REUSABLE>

set -Eeuo pipefail

APP="camino-backup-signer"
REPOSITORY="StJames-way/DB-backup"
GUARDIAN_WORKFLOW="backup-guardian.yml"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-$HOME/.local/bin/deploy-backup-signer}"
VERIFY_SCRIPT="${VERIFY_SCRIPT:-$HOME/.local/bin/verify-backup-signer-deployment}"
EXPECTED_SHA="${1:-}"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]] || \
  fail "indica el SHA completo del reusable"

command -v fly >/dev/null || fail "falta flyctl"
command -v gh >/dev/null || fail "falta GitHub CLI"
command -v jq >/dev/null || fail "falta jq"
[[ -x "$DEPLOY_SCRIPT" ]] || fail "no existe $DEPLOY_SCRIPT"

[[ -z "${FLY_API_TOKEN:-}" ]] || \
  fail "FLY_API_TOKEN debe estar ausente; usa fly auth login local"

fly auth whoami >/dev/null
gh auth status >/dev/null 2>&1

echo '[1/4] Despliegue manual seguro...'
"$DEPLOY_SCRIPT" "$EXPECTED_SHA"

echo '[2/4] Verificación del signer desplegado...'
if [[ -x "$VERIFY_SCRIPT" ]]; then
  "$VERIFY_SCRIPT" "$EXPECTED_SHA"
else
  curl --connect-timeout 10 --max-time 90 -fsS \
    "https://${APP}.fly.dev/healthz" | jq -e '.status == "ok"'
  curl --connect-timeout 10 --max-time 90 -fsS \
    "https://${APP}.fly.dev/readyz" | jq -e '.status == "ready"'
fi

echo '[3/4] Disparando Backup Guardian...'
STARTED_AT="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
MAIN_SHA="$(gh api "repos/${REPOSITORY}/commits/main" --jq '.sha')"

gh workflow run "$GUARDIAN_WORKFLOW" \
  --repo "$REPOSITORY" \
  --ref main \
  --field production_canary=true \
  --field check_supabase_trigger=true

GUARDIAN_RUN_ID=""
for ((attempt = 1; attempt <= 80; attempt += 1)); do
  GUARDIAN_RUN_ID="$(
    gh run list \
      --repo "$REPOSITORY" \
      --workflow "$GUARDIAN_WORKFLOW" \
      --event workflow_dispatch \
      --branch main \
      --limit 20 \
      --json databaseId,createdAt,headSha \
    | jq -r \
        --arg started "$STARTED_AT" \
        --arg sha "$MAIN_SHA" '
          [
            .[]
            | select(.createdAt >= $started)
            | select(.headSha == $sha)
          ]
          | sort_by(.createdAt)
          | last
          | .databaseId // empty'
  )"

  if [[ -n "$GUARDIAN_RUN_ID" ]]; then
    break
  fi
  sleep 3
done

[[ -n "$GUARDIAN_RUN_ID" ]] || \
  fail "no apareció el run de Backup Guardian"

echo "Guardian run_id=$GUARDIAN_RUN_ID"

echo '[4/4] Esperando validación extremo a extremo...'
gh run watch "$GUARDIAN_RUN_ID" \
  --repo "$REPOSITORY" \
  --exit-status

printf '\nRESULTADO: despliegue y backup canario verificados correctamente.\n'
