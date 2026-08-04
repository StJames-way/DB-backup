#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-StJames-way/DB-backup}"
WORKFLOW='supabase-backup-dispatch.yml'

BEFORE="$(gh run list --repo "$REPO" --workflow "$WORKFLOW"   --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // 0')"

gh workflow run "$WORKFLOW" --repo "$REPO"

RUN_ID=''
for _ in $(seq 1 30); do
  CANDIDATE="$(gh run list --repo "$REPO" --workflow "$WORKFLOW"     --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // 0')"
  if [ "$CANDIDATE" != "$BEFORE" ] && [ "$CANDIDATE" != 0 ]; then
    RUN_ID="$CANDIDATE"; break
  fi
  sleep 2
done

[ -n "$RUN_ID" ] || { echo 'No se encontró run nuevo' >&2; exit 1; }
echo "RUN_ID=$RUN_ID"
gh run watch "$RUN_ID" --repo "$REPO" --compact --exit-status

BASE="$(gh api "repos/$REPO/contents/manifests?ref=backups-signed-latest-30"   --jq '.[].name' | sort | tail -n1 | sed 's/\.json$//')"
[ -n "$BASE" ] || exit 1

echo "BASE=$BASE"
gh api "repos/$REPO/contents/signatures?ref=backups-signed-latest-30"   --jq '.[].name' | grep -E "^${BASE}\.(sig|json)$"
gh api "repos/$REPO/contents/encrypted_backups?ref=backups-signed-latest-30"   --jq '.[].name' | grep -E "^${BASE}\.dump\.age\.[a-z]{3}\.part$"

echo 'OK: workflow y artefactos publicados'
