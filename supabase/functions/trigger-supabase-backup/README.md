# Edge Function `trigger-supabase-backup`

Dispara `repository_dispatch` en `StJames-way/DB-backup`. No realiza el backup
ni accede a la base de datos: únicamente solicita a GitHub que inicie el
workflow.

## Secretos requeridos

```bash
supabase secrets set \
  GITHUB_BACKUP_DISPATCH_TOKEN='github_pat_REDACTADO' \
  GITHUB_BACKUP_REPOSITORY_OWNER='StJames-way' \
  GITHUB_BACKUP_REPOSITORY='DB-backup' \
  BACKUP_AGE_RECIPIENT='age1REDACTADO' \
  SUPABASE_BACKUP_TRIGGER_SECRET='GENERA_UN_SECRETO_ALEATORIO_DE_32_BYTES'
```

Generación del secreto de llamada:

```bash
openssl rand -hex 32
```

El token de GitHub debe ser fine-grained, limitado exclusivamente al
repositorio `StJames-way/DB-backup`, con:

```text
Repository permissions → Contents: Read and write
```

No debe tener permisos de organización ni acceso a otros repositorios.

## Despliegue

Como la función usa un secreto propio para autenticar la llamada programada:

```bash
supabase functions deploy trigger-supabase-backup --no-verify-jwt
```

`--no-verify-jwt` no convierte la función en anónima: `index.ts` exige
`Authorization: Bearer <SUPABASE_BACKUP_TRIGGER_SECRET>`. No uses el secreto
`service_role` como secreto de cron.

## Prueba manual

```bash
curl --fail-with-body \
  -X POST \
  -H "Authorization: Bearer $SUPABASE_BACKUP_TRIGGER_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"force":false}' \
  "https://PROJECT_REF.supabase.co/functions/v1/trigger-supabase-backup"
```

GitHub responde `204` al dispatch. La Edge Function transforma ese resultado
en `202 Accepted`.

## Programación con Vault + pg_cron

Guarda el secreto de llamada en Supabase Vault:

```sql
select vault.create_secret(
  'REEMPLAZAR_CON_EL_MISMO_SECRETO_DE_32_BYTES',
  'backup_trigger_secret',
  'Token que autoriza pg_cron a disparar el backup'
);
```

Programa una ejecución diaria, por ejemplo a las 02:30 UTC:

```sql
select cron.schedule(
  'daily-supabase-backup',
  '30 2 * * *',
  $$
  select net.http_post(
    url := 'https://PROJECT_REF.supabase.co/functions/v1/trigger-supabase-backup',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization',
      'Bearer ' || (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'backup_trigger_secret'
        limit 1
      )
    ),
    body := '{"force":false}'::jsonb,
    timeout_milliseconds := 20000
  );
  $$
);
```

Comprueba que `pg_cron`, `pg_net` y Vault están disponibles en el proyecto.
No incrustes el token de GitHub en SQL: solo debe existir como secreto de la
Edge Function.
