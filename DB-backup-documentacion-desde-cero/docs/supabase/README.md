# Supabase Edge Function

## Archivo documentado

```text
docs/supabase/index.ts
```

## Archivo operativo local

```text
supabase/functions/trigger-github-backup/index.ts
```

## Función desplegada

```text
trigger-github-backup
```

## Instalar o actualizar

Desde la raíz de `DB-backup`:

Declara en `supabase/config.toml`:

```toml
[functions.trigger-github-backup]
verify_jwt = false
```

Después:

```bash
mkdir -p supabase/functions/trigger-github-backup

install -m 0644 \
  docs/supabase/index.ts \
  supabase/functions/trigger-github-backup/index.ts

supabase functions deploy \
  trigger-github-backup \
  --project-ref urfbxknxmzcvgogkixdq \
  --no-verify-jwt
```

## Reloj automático

La función debe ser invocada por Supabase Cron (`pg_cron`) mediante `pg_net`. El secreto de la cabecera `x-backup-trigger-secret` se guarda en Supabase Vault. El PAT de GitHub no se guarda en SQL. La guía principal contiene el SQL completo.

## Regla de sincronización

Cada vez que cambies `docs/supabase/index.ts`:

1. copia al path operativo;
2. despliega;
3. ejecuta `test-supabase-backup-e2e`;
4. confirma un `repository_dispatch` nuevo y un commit nuevo de almacenamiento.
