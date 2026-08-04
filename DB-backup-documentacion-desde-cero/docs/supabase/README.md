# Supabase: origen, rol y disparador

## 1. Base de datos

El backup usa Session pooler con el rol `backup_reader`. El workflow no usa la
Edge Function para leer datos; conecta directamente por PostgreSQL TLS.

Consulta:

```text
aws-0-eu-west-1.pooler.supabase.com:5432
backup_reader.urfbxknxmzcvgogkixdq
sslmode=verify-full
```

Usa `docs/create-backup-reader-role.sql` y
`docs/configure-supabase-verified-tls.md`.

## 2. Edge Function

Archivo operativo:

```text
supabase/functions/trigger-supabase-backup/index.ts
```

Función desplegada:

```text
trigger-supabase-backup
```

Solo crea `repository_dispatch`; no hace `pg_dump` ni conoce la password DB.

## Secretos

```text
GITHUB_BACKUP_DISPATCH_TOKEN
GITHUB_BACKUP_REPOSITORY_OWNER
GITHUB_BACKUP_REPOSITORY
BACKUP_AGE_RECIPIENT
SUPABASE_BACKUP_TRIGGER_SECRET
```

## Despliegue

```bash
supabase functions deploy trigger-supabase-backup   --project-ref urfbxknxmzcvgogkixdq --no-verify-jwt
```

`--no-verify-jwt` no la hace anónima: el código exige un Bearer secret propio.

## Cron

Invócala con `pg_cron + pg_net`. Guarda el trigger secret en Vault. El PAT de
GitHub solo vive como secreto de la Edge Function y nunca en SQL.
