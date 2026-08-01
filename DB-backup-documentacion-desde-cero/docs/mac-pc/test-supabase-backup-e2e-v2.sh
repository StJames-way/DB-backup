#!/usr/bin/env bash
#
# test-supabase-backup-e2e-v2.sh
#
# Compatible con la Edge Function aportada por el usuario:
# - secreto remoto: BACKUP_TRIGGER_SECRET
# - cabecera: x-backup-trigger-secret
# - forzado: ?force=1
# - respuesta correcta: HTTP 200 y status "Pipeline disparado con éxito"
#
# Uso:
#
#   export SUPABASE_PROJECT_REF="xxxxxxxxxxxxxxxxxxxx"
#   export SUPABASE_FUNCTION_NAME="nombre-real-de-la-funcion"
#   ./test-supabase-backup-e2e-v2.sh
#

set -Eeuo pipefail

REPOSITORY="StJames-way/DB-backup"
WORKFLOW_FILE="supabase-backup-dispatch.yml"
STORAGE_BRANCH="backups-signed-latest-30"

PROJECT_REF="${SUPABASE_PROJECT_REF:-}"
FUNCTION_NAME="${SUPABASE_FUNCTION_NAME:-}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for tool in gh curl jq mktemp sort; do
  command -v "$tool" >/dev/null 2>&1 || die "falta el comando: $tool"
done

gh auth status >/dev/null 2>&1 || die "ejecuta: gh auth login"

[[ "$PROJECT_REF" =~ ^[a-z0-9-]+$ ]] || \
  die "define SUPABASE_PROJECT_REF con el project ref real"

[[ "$FUNCTION_NAME" =~ ^[A-Za-z0-9_-]+$ ]] || \
  die "define SUPABASE_FUNCTION_NAME con el nombre real de la Edge Function"

FUNCTION_URL="https://${PROJECT_REF}.supabase.co/functions/v1/${FUNCTION_NAME}?force=1"

TMPDIR_LOCAL="$(mktemp -d "${TMPDIR:-/tmp}/supabase-backup-e2e.XXXXXX")"

cleanup() {
  rm -rf "$TMPDIR_LOCAL"
  unset BACKUP_TRIGGER_SECRET || true
}
trap cleanup EXIT INT TERM

printf 'Introduce BACKUP_TRIGGER_SECRET (no se mostrará): '
IFS= read -r -s BACKUP_TRIGGER_SECRET
printf '\n'

[[ -n "$BACKUP_TRIGGER_SECRET" ]] || die "BACKUP_TRIGGER_SECRET está vacío"

printf '\n[1/7] Capturando el estado anterior...\n'

BEFORE_RUN_ID="$(
  gh run list \
    --repo "$REPOSITORY" \
    --workflow "$WORKFLOW_FILE" \
    --event repository_dispatch \
    --limit 10 \
    --json databaseId,createdAt \
    --jq 'if length == 0 then "0" else (max_by(.createdAt).databaseId | tostring) end'
)"

BEFORE_STORAGE_SHA="$(
  gh api \
    "repos/${REPOSITORY}/git/ref/heads/${STORAGE_BRANCH}" \
    --jq '.object.sha' \
    2>/dev/null || true
)"

printf 'Run anterior: %s\n' "$BEFORE_RUN_ID"
printf 'Storage anterior: %s\n' "${BEFORE_STORAGE_SHA:-<no existe>}"

printf '\n[2/7] Invocando la Edge Function real...\n'

EDGE_RESPONSE="$TMPDIR_LOCAL/edge-response.json"

EDGE_HTTP_STATUS="$(
  curl \
    --connect-timeout 15 \
    --max-time 45 \
    --silent \
    --show-error \
    --output "$EDGE_RESPONSE" \
    --write-out '%{http_code}' \
    --request POST \
    --header "x-backup-trigger-secret: ${BACKUP_TRIGGER_SECRET}" \
    --header 'Content-Type: application/json' \
    "$FUNCTION_URL"
)"

unset BACKUP_TRIGGER_SECRET

printf 'HTTP Edge Function: %s\n' "$EDGE_HTTP_STATUS"
jq . "$EDGE_RESPONSE" 2>/dev/null || cat "$EDGE_RESPONSE"

if [[ "$EDGE_HTTP_STATUS" == "401" ]]; then
  die "401: secreto incorrecto o verify_jwt sigue activo antes de ejecutar index.ts"
fi

[[ "$EDGE_HTTP_STATUS" == "200" ]] || \
  die "la Edge Function no devolvió HTTP 200"

jq -e \
  '.status == "Pipeline disparado con éxito"
   and (.local_date | type == "string" and length == 10)
   and (.age_recipient_sha256 | test("^[0-9a-f]{64}$"))' \
  "$EDGE_RESPONSE" >/dev/null || \
  die "la respuesta no coincide con el contrato de index.ts"

printf 'OK: index.ts aceptó la petición y GitHub respondió correctamente.\n'

printf '\n[3/7] Esperando un repository_dispatch nuevo...\n'

RUN_ID=""
for ((attempt = 1; attempt <= 60; attempt += 1)); do
  CANDIDATE="$(
    gh run list \
      --repo "$REPOSITORY" \
      --workflow "$WORKFLOW_FILE" \
      --event repository_dispatch \
      --limit 10 \
      --json databaseId,createdAt \
      --jq 'if length == 0 then "0" else (max_by(.createdAt).databaseId | tostring) end'
  )"

  if [[ "$CANDIDATE" != "0" && "$CANDIDATE" != "$BEFORE_RUN_ID" ]]; then
    RUN_ID="$CANDIDATE"
    break
  fi

  sleep 3
done

[[ -n "$RUN_ID" ]] || die "GitHub no creó un repository_dispatch nuevo"

printf 'Nuevo GitHub run_id: %s\n' "$RUN_ID"

printf '\n[4/7] Esperando el pipeline completo...\n'

gh run watch \
  "$RUN_ID" \
  --repo "$REPOSITORY" \
  --exit-status

RUN_JSON="$TMPDIR_LOCAL/run.json"

gh run view \
  "$RUN_ID" \
  --repo "$REPOSITORY" \
  --json event,status,conclusion,url,headBranch,headSha,jobs \
  > "$RUN_JSON"

jq '{
  event,
  status,
  conclusion,
  url,
  headBranch,
  headSha
}' "$RUN_JSON"

jq -e \
  '.event == "repository_dispatch"
   and .status == "completed"
   and .conclusion == "success"' \
  "$RUN_JSON" >/dev/null || \
  die "el run no terminó correctamente como repository_dispatch"

for required_step in \
  "Validate trigger and configuration" \
  "Create, encrypt, sign and verify backup" \
  "Publish one-commit storage snapshot"
do
  jq -e \
    --arg step "$required_step" \
    '[
       .jobs[].steps[]
       | select(.name == $step and .conclusion == "success")
     ] | length >= 1' \
    "$RUN_JSON" >/dev/null || \
    die "no quedó verde el paso: $required_step"
done

printf 'OK: trigger, dump, cifrado, firma, verificación y publicación están verdes.\n'

printf '\n[5/7] Confirmando un commit nuevo de almacenamiento...\n'

AFTER_STORAGE_SHA=""
for ((attempt = 1; attempt <= 40; attempt += 1)); do
  AFTER_STORAGE_SHA="$(
    gh api \
      "repos/${REPOSITORY}/git/ref/heads/${STORAGE_BRANCH}" \
      --jq '.object.sha' \
      2>/dev/null || true
  )"

  if [[ -n "$AFTER_STORAGE_SHA" && "$AFTER_STORAGE_SHA" != "$BEFORE_STORAGE_SHA" ]]; then
    break
  fi

  sleep 3
done

[[ -n "$AFTER_STORAGE_SHA" ]] || die "no existe la rama de almacenamiento"
[[ "$AFTER_STORAGE_SHA" != "$BEFORE_STORAGE_SHA" ]] || \
  die "no apareció un commit nuevo pese a force=1"

printf 'Commit nuevo: %s\n' "$AFTER_STORAGE_SHA"

printf '\n[6/7] Localizando el manifiesto publicado para este run...\n'

MANIFEST_LIST="$TMPDIR_LOCAL/manifests.txt"

gh api \
  "repos/${REPOSITORY}/contents/manifests?ref=${STORAGE_BRANCH}" \
  --jq '.[].name' \
  | sort -r \
  > "$MANIFEST_LIST"

MANIFEST_NAME=""
MANIFEST_LOCAL="$TMPDIR_LOCAL/manifest.json"

while IFS= read -r candidate; do
  [[ -n "$candidate" ]] || continue

  gh api \
    -H 'Accept: application/vnd.github.raw+json' \
    "repos/${REPOSITORY}/contents/manifests/${candidate}?ref=${STORAGE_BRANCH}" \
    > "$MANIFEST_LOCAL"

  candidate_run_id="$(jq -r '.provenance.run_id // ""' "$MANIFEST_LOCAL")"

  if [[ "$candidate_run_id" == "$RUN_ID" ]]; then
    MANIFEST_NAME="$candidate"
    break
  fi
done < "$MANIFEST_LIST"

[[ -n "$MANIFEST_NAME" ]] || \
  die "no se encontró un manifiesto con provenance.run_id=${RUN_ID}"

jq -e \
  --arg run "$RUN_ID" \
  --arg repo "$REPOSITORY" \
  '
    .schema_version == 5
    and .provenance.run_id == $run
    and .provenance.repository == $repo
    and (.part_count | type == "number" and . > 0)
    and .part_count == (.parts | length)
    and ([.parts[].size_bytes > 0] | all)
    and ([.parts[].sha256 | test("^[0-9a-f]{64}$")] | all)
  ' \
  "$MANIFEST_LOCAL" >/dev/null || \
  die "el manifiesto publicado no cumple el contrato esperado"

printf 'Manifiesto: %s\n' "$MANIFEST_NAME"

printf '\n[7/7] Comprobando firma y existencia de las partes...\n'

BASE="${MANIFEST_NAME%.json}"
SIGNATURE_PATH="signatures/${BASE}.sig"
SIGNATURE_META_PATH="signatures/${BASE}.json"

gh api \
  "repos/${REPOSITORY}/contents/${SIGNATURE_PATH}?ref=${STORAGE_BRANCH}" \
  >/dev/null || die "falta la firma publicada"

SIGNATURE_META_LOCAL="$TMPDIR_LOCAL/signature-meta.json"

gh api \
  -H 'Accept: application/vnd.github.raw+json' \
  "repos/${REPOSITORY}/contents/${SIGNATURE_META_PATH}?ref=${STORAGE_BRANCH}" \
  > "$SIGNATURE_META_LOCAL"

jq -e \
  '
    .provider == "backup-signer-openbao-transit"
    and .algorithm == "ed25519"
    and (.key_version | type == "number" and . >= 1)
    and (.manifest_sha256 | test("^[0-9a-f]{64}$"))
  ' \
  "$SIGNATURE_META_LOCAL" >/dev/null || \
  die "los metadatos de firma son incorrectos"

PART_FAILURES=0

while IFS=$'\t' read -r part_name expected_size expected_sha; do
  PART_META="$TMPDIR_LOCAL/part-meta.json"

  if ! gh api \
    "repos/${REPOSITORY}/contents/${part_name}?ref=${STORAGE_BRANCH}" \
    > "$PART_META"
  then
    printf 'ERROR: falta %s\n' "$part_name" >&2
    PART_FAILURES=$((PART_FAILURES + 1))
    continue
  fi

  actual_size="$(jq -r '.size' "$PART_META")"

  if [[ "$actual_size" != "$expected_size" ]]; then
    printf 'ERROR: tamaño incorrecto en %s\n' "$part_name" >&2
    PART_FAILURES=$((PART_FAILURES + 1))
  fi

  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || {
    printf 'ERROR: digest inválido en %s\n' "$part_name" >&2
    PART_FAILURES=$((PART_FAILURES + 1))
  }
done < <(
  jq -r '.parts[] | [.name, (.size_bytes | tostring), .sha256] | @tsv' \
    "$MANIFEST_LOCAL"
)

[[ "$PART_FAILURES" == "0" ]] || die "falló la comprobación de partes"

printf '\n============================================================\n'
printf 'PRUEBA E2E DESDE index.ts: CORRECTA\n'
printf '============================================================\n'
printf 'GitHub run_id:  %s\n' "$RUN_ID"
printf 'Storage commit: %s\n' "$AFTER_STORAGE_SHA"
printf 'Manifest:       %s\n' "$MANIFEST_NAME"
