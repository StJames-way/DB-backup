# Herramientas para Mac y Windows WSL

## Qué se instala realmente en el ordenador

Scripts Bash:

```text
$HOME/.local/bin/deploy-backup-signer
$HOME/.local/bin/verify-backup-signer-deployment
$HOME/.local/bin/deploy-backup-signer-and-verify
$HOME/.local/bin/test-supabase-backup-e2e
```

## Qué NO se ejecuta en el ordenador

`backup-guardian-v4.yml` es un workflow de GitHub. El ordenador solo lo copia a:

```text
.github/workflows/backup-guardian.yml
```

Después lo ejecuta GitHub Actions.

## Instalar todo

Desde la raíz de `DB-backup`:

```bash
bash docs/mac-pc/install-local-tools.sh
bash docs/mac-pc/install-backup-guardian.sh
```

## Ejecutar el despliegue completo del signer

```bash
unset FLY_API_TOKEN

"$HOME/.local/bin/deploy-backup-signer-and-verify" \
  9df9f393517fffddca9e4bb7264211010cb0912b
```

## Ejecutar el E2E desde Supabase

```bash
export SUPABASE_PROJECT_REF="urfbxknxmzcvgogkixdq"
export SUPABASE_FUNCTION_NAME="trigger-github-backup"

"$HOME/.local/bin/test-supabase-backup-e2e"
```
