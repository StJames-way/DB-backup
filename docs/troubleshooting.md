# Resolución de problemas

## Método de diagnóstico

1. identifica el paso exacto de GitHub;
2. obtén `--log-failed` del job;
3. abre Worker y Fly logs antes de repetir;
4. no cambies varias capas a la vez;
5. conserva escala a cero durante las pruebas.

```bash
GH_PAGER=cat gh run view "$RUN_ID"   --repo StJames-way/DB-backup   --job "$JOB_ID" --log-failed
```

## Supabase

### `sslmode=verify-full exactamente una vez`

La URL del secret carece del parámetro, lo repite o lo codificó mal. Reconstruye
la URL; no edites a ciegas el valor secreto.

### `too many connections for role "backup_reader"`

Causa observada durante la puesta en marcha. Verifica:

```sql
SELECT pid, application_name, state, backend_start
FROM pg_stat_activity
WHERE usename = 'backup_reader';
```

Comprueba `rolconnlimit=10`. Cierra sesiones residuales solo cuando hayas
confirmado que no corresponden a un backup activo.

### `password authentication failed`

Contraseña o URL encoding incorrectos.

### `Tenant or user not found`

Falta `.PROJECT_REF` en el usuario del pooler o el host es de otro proyecto.

### `certificate verify failed`

CA, hostname o pooler equivocados. No cambies a `sslmode=require`.

### `permission denied for table/sequence/schema`

Añade `USAGE` al schema y `SELECT` a tablas/secuencias, incluyendo default
privileges del owner que creará objetos futuros.

## Cloudflare Worker

### `github_jwks_fetch_failed`

El Worker no pudo obtener las claves públicas de GitHub. La versión actual
reintenta y cachea. Revisa el log ampliado (`name`, `message`, `causeName`,
`causeMessage`) y confirma que el Worker parcheado fue realmente desplegado.

### `github_oidc_rejected`

Un claim no coincide. Compara:

- repository y IDs;
- caller workflow;
- reusable workflow y SHA;
- `refs/heads/main`;
- evento;
- audiencia.

### `Signer unavailable` / `signer_upstream_exception`

Revisa VPC Service, Tunnel, Flycast y estado de las máquinas:

```bash
npx wrangler vpc service get '<SERVICE_ID>'
fly status -a camino-backup-tunnel
fly machine list -a camino-backup-signer
```

### `/readyz` devuelve `503`

Puede ser arranque en frío o OpenBao no listo. Mira los tres logs y reintenta
durante 60 segundos. No pongas `min_machines_running=1` como arreglo.

## Signer

### `403 Gateway no autorizado`

`BACKUP_GATEWAY_TOKEN` no coincide entre Worker y Fly.

### `403 Identidad o manifiesto no autorizados`

El signer rechazó OIDC o procedencia. Revisa el SHA de confianza y claims.

### `502 No se pudo completar la firma`

OpenBao, AppRole, CA o policy.

### Health check inicial rojo y después verde

Durante el arranque Uvicorn puede tardar varios segundos. Es normal si termina
en `readyz 200` y el health check pasa.

## GitHub

### Exit code 22

`curl --fail` recibió HTTP >= 400. Obtén logs de Worker para saber si fue 403,
429, 502 o 503.

### Exit code 2 en pocos segundos

Frecuente en `psql`: mira la línea inmediatamente anterior. No presupongas que
es Cloudflare si el Worker no recibió ninguna petición.

### No aparece el backup nuevo

Revisa si el workflow decidió `skip=true` porque ya existe uno del día. Usa el
input `force` únicamente para canarios controlados.

## Backup Recovery PWA

### La web no abre o aparece una versión antigua

- URL correcta: `https://stjames-way.github.io/backup-recovery-pwa/`;
- recarga forzada y prueba una ventana privada;
- comprueba el estado del workflow Pages del repo `backup-recovery-pwa`;
- si Pages no está disponible, ejecuta una copia local fijada o usa el kit CLI;
- registra el commit/build utilizado en la recuperación.

### No detecta la carpeta

Selecciona la raíz que contiene exactamente:

```text
manifests/
signatures/
encrypted_backups/
```

No selecciones únicamente `encrypted_backups/`. En Safari u otros navegadores
con soporte limitado, usa la carga manual o genera/usa el kit de terminal.

### Firma inválida

Comprueba que manifiesto y `.sig` tienen el mismo timestamp/base, que la clave
pública corresponde a la versión indicada y que el trust JSON no pertenece a
otro proyecto. No omitas la firma para continuar.

### Falta una parte o el SHA-256 no coincide

Vuelve a obtener el snapshot desde el commit fijado de
`backups-signed-latest-30`. No renombres, edites ni combines partes de fechas
distintas. Los sufijos `aaa`, `aab`, etc. son correctos.

### El JSON de metadatos no está

`signatures/<base>.json` es opcional para la verificación criptográfica
principal. La PWA puede mostrar una advertencia, pero todavía debe exigir el
manifiesto, la firma `.sig`, la clave pública y todas las partes.

### La PWA pide la identidad privada `age`

Detente. La aplicación oficial no necesita ni debe solicitar esa identidad.
Verifica la URL, el certificado, el repositorio/build y usa una copia local
confiable.

### El `.dump.age` se creó pero no puedo abrirlo

Es correcto: continúa cifrado. Debes descifrarlo fuera del navegador con la
identidad privada offline y después validar `pg_restore --list`.

## Nombres aparentemente duplicados

No es un error:

```text
manifests/<base>.json
signatures/<base>.json
```

Son rutas distintas. Tampoco es un error que las partes terminen en `aaa`,
`aab` en vez de números.
