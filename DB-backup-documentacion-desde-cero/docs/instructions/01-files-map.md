# Mapa de archivos

## Repositorio DB-backup

```text
.github/workflows/
  supabase-backup-dispatch.yml
  supabase-age-openbao-reusable.yml
  backup-guardian.yml
config/
  age-recipient.txt
  backup-recovery-trust.json
  backup-signing-public-key.pem
  prod-ca-2021.crt
tools/backup/
  build_manifest.py
  verify_backup_set.py
  verify_signature.py
  restore_backup.py
  verify_plaintext_dump.py
docs/
  GUIA_BACKUP_DESDE_CERO.md
  backup-architecture.md
  cloudflare-private-gateway.md
  configure-supabase-verified-tls.md
  create-backup-reader-role.sql
  current-deployment-contract.md
  disaster-recovery.md
  operations-runbook.md
  port-to-another-project.md
  recovery-drill.md
  security-boundaries.md
  troubleshooting.md
supabase/functions/trigger-supabase-backup/
```

## Repositorio/paquete signer

```text
app/
  config.py
  github_oidc.py
  main.py
  openbao.py
  perimeter.py
  schemas.py
  security.py
certs/camino-openbao-ca.pem
fly.toml
Dockerfile
openbao/backup-signer-policy.hcl
```

## Paquete Cloudflare

```text
worker/
  src/index.js
  wrangler.toml
  package.json
tunnel-fly/
  Dockerfile
  fly.toml
```

## Offline

```text
identidad privada age
copias de recuperación
actas de recovery drill
```
