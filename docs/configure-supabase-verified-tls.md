# Supabase con TLS verificado (`verify-full`)

## Objetivo

No basta con cifrar el tráfico. `verify-full` comprueba:

1. que el servidor presenta una cadena válida hasta la CA aprobada;
2. que el hostname solicitado coincide con el certificado;
3. que la sesión PostgreSQL está realmente usando SSL.

## CA aprobada

Archivo versionado:

```text
config/prod-ca-2021.crt
```

Huella DER SHA-256 actual:

```text
807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa
```

Comprobarla:

```bash
openssl x509   -in config/prod-ca-2021.crt   -outform DER |
sha256sum
```

## URL del pooler

Formato para Session pooler:

```text
postgresql://backup_reader.<PROJECT_REF>:<PASSWORD_URLENCODED>@<POOLER_HOST>:5432/postgres?sslmode=verify-full
```

Despliegue actual:

```text
Usuario: backup_reader.urfbxknxmzcvgogkixdq
Host:    aws-0-eu-west-1.pooler.supabase.com
Port:    5432
DB:      postgres
```

La contraseña debe codificarse para URL. No pegues caracteres especiales sin
`percent-encoding`.

## Prueba local sin exponer la URL

```bash
export PGHOST='aws-0-eu-west-1.pooler.supabase.com'
export PGPORT='5432'
export PGDATABASE='postgres'
export PGUSER='backup_reader.urfbxknxmzcvgogkixdq'
export PGPASSWORD='<PASSWORD>'
export PGSSLMODE='verify-full'
export PGSSLROOTCERT="$PWD/config/prod-ca-2021.crt"
export PGAPPNAME='backup-reader-local-test'

psql --no-psqlrc   --command 'SELECT current_user, session_user, current_database();'

psql --no-psqlrc   --tuples-only --no-align   --command 'SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();'
```

La segunda consulta debe devolver:

```text
t
```

## Guardar el secret en GitHub

```bash
printf '%s' "$SUPABASE_DB_URL" |
gh secret set SUPABASE_DB_URL --repo StJames-way/DB-backup
```

No uses `gh secret set ... --body "$SUPABASE_DB_URL"` en una sesión con tracing.

## Validaciones del workflow

El reusable:

- rechaza URL no PostgreSQL;
- exige `sslmode=verify-full` exactamente una vez;
- instala la CA en un directorio confiable temporal;
- verifica la huella de la CA;
- usa `PGSSLMODE=verify-full` y `PGSSLROOTCERT` como defensa adicional;
- consulta `pg_stat_ssl` antes del dump.

## Errores frecuentes

### `certificate verify failed`

Host incorrecto, CA equivocada o certificado rotado. Copia el host exacto de
Supabase `Connect -> Session pooler`. No rebajes a `require`.

### `Tenant or user not found`

El usuario del pooler debe incluir el project ref:

```text
backup_reader.<PROJECT_REF>
```

### `too many connections for role "backup_reader"`

Revisa `rolconnlimit`, sesiones residuales y ejecuciones solapadas. El valor
actual es 10 y el workflow usa un `concurrency` global.

### `password authentication failed`

Rota la contraseña del rol, genera de nuevo la URL codificada y actualiza el
secret. No cambies la CA ni desactives TLS para resolver un error de password.
