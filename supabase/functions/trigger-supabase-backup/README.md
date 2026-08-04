# Edge Function `trigger-supabase-backup`

Esta función no extrae la base ni contacta con Cloudflare, Fly u OpenBao. Su único cometido es crear un `repository_dispatch` autenticado en GitHub. El workflow posterior conecta a Supabase por PostgreSQL TLS, cifra el dump y envía solo el manifiesto y el OIDC al Cloudflare Backup Gateway.

## Secretos

```text
GITHUB_BACKUP_DISPATCH_TOKEN
GITHUB_BACKUP_REPOSITORY_OWNER
GITHUB_BACKUP_REPOSITORY
BACKUP_AGE_RECIPIENT
SUPABASE_BACKUP_TRIGGER_SECRET
```

El PAT debe estar limitado al repositorio de backup. El trigger secret debe ser distinto del `service_role`.

## Despliegue

```bash
supabase functions deploy trigger-supabase-backup --project-ref PROJECT_REF --no-verify-jwt
```

`--no-verify-jwt` no la hace anónima: el código exige `Authorization: Bearer <SUPABASE_BACKUP_TRIGGER_SECRET>` y compara el valor en tiempo constante.

## Cron

Usa Supabase Vault + `pg_cron` + `pg_net`. No guardes el PAT de GitHub dentro de SQL. La función envía al dispatch la política, versión de formato y SHA-256 del recipient `age`; GitHub vuelve a comprobar esos valores.
