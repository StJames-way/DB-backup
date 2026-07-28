#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="${DISPATCH_TEMPLATE:-$REPO_ROOT/.github/workflows/supabase-backup-dispatch.yml.template}"
OUTPUT="${DISPATCH_OUTPUT:-$REPO_ROOT/.github/workflows/supabase-backup-dispatch.yml}"

: "${TRUSTED_WORKFLOW_REPOSITORY:?Define TRUSTED_WORKFLOW_REPOSITORY, por ejemplo owner/backup-workflows}"
: "${TRUSTED_WORKFLOW_SHA:?Define TRUSTED_WORKFLOW_SHA con 40 caracteres hexadecimales}"

[[ "$TRUSTED_WORKFLOW_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo "Repositorio de workflow inválido: $TRUSTED_WORKFLOW_REPOSITORY" >&2
  exit 1
}
[[ "$TRUSTED_WORKFLOW_SHA" =~ ^[0-9a-fA-F]{40}$ ]] || {
  echo "TRUSTED_WORKFLOW_SHA debe tener 40 caracteres hexadecimales" >&2
  exit 1
}
test -f "$TEMPLATE"

python3 - "$TEMPLATE" "$OUTPUT" "$TRUSTED_WORKFLOW_REPOSITORY" "${TRUSTED_WORKFLOW_SHA,,}" <<'PY'
from pathlib import Path
import sys

template, output, repository, sha = sys.argv[1:]
text = Path(template).read_text(encoding="utf-8")
text = text.replace("@@WORKFLOW_REPOSITORY@@", repository)
text = text.replace("@@WORKFLOW_SHA@@", sha)
if "@@" in text:
    raise SystemExit("Quedan marcadores sin sustituir")
Path(output).write_text(text, encoding="utf-8")
PY

chmod 0644 "$OUTPUT"
echo "Workflow generado: $OUTPUT"
echo "Ref inmutable: $TRUSTED_WORKFLOW_REPOSITORY@$TRUSTED_WORKFLOW_SHA"
