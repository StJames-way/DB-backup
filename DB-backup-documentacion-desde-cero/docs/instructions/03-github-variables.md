# Variables de GitHub de `StJames-way/DB-backup`

## La diferencia entre variable y secreto

- Una **variable** contiene información pública o de configuración.
- Un **secreto** contiene algo que permite entrar o hacer daño si se roba.

En `DB-backup`, el único secreto que necesita el workflow es:

```text
SUPABASE_DB_URL
```

No se escribe en ningún archivo. Se guarda en:

```text
DB-backup → Settings → Secrets and variables → Actions → Secrets
```

## Tabla completa de las variables que tienes ahora

| Variable | Valor actual | De dónde sale | ¿La lee hoy el workflow? | Qué pasa si la cambias solo en GitHub |
|---|---|---|---|---|
| `BACKUP_AGE_RECIPIENT` | `age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae` | Es la parte pública obtenida con `age-keygen -y` desde la identidad privada offline | **Sí**. El caller la pasa al reusable | Cambia el recipient que intenta usar el workflow, pero fallará si no actualizas también la huella esperada y Supabase |
| `BACKUP_ALLOWED_REF` | `refs/heads/main` | Es la rama autorizada. Debe coincidir con `ALLOWED_REF` de `backup-signer/fly.toml` | **No** en los workflows actuales; es una copia de control | No cambia el comportamiento real |
| `BACKUP_DISPATCH_SOURCE` | `supabase-edge-function` | Es el nombre que envía `docs/supabase/index.ts` en el payload | **No** como variable de repo; el valor llega en el payload y se valida en el reusable | No cambia el comportamiento real |
| `BACKUP_FORMAT_VERSION` | `5` | Es la versión del contrato del manifiesto y del payload | **No** como variable de repo; está validada en Edge Function, caller y reusable | No cambia el comportamiento real |
| `BACKUP_PART_SIZE_BYTES` | `94371840` | `90 × 1024 × 1024`; son 90 MiB | **No**; el reusable usa actualmente `split --bytes=90M` | No cambia el tamaño real |
| `BACKUP_POLICY` | `daily_full_age_encrypted_openbao_signed_retain_last_30_verified` | Es el nombre exacto de la política que acuerdan Supabase y GitHub | **No** como variable de repo; está en el payload y en las validaciones | No cambia el comportamiento real |
| `BACKUP_RETENTION_COUNT` | `30` | Decisión de conservar los 30 backups verificados más nuevos | **No**; el reusable tiene `30` en su código | No cambia la retención real |
| `BACKUP_SIGNER_URL` | `https://camino-backup-signer.fly.dev` | Es la URL pública de la app Fly `camino-backup-signer` | **Sí**. El caller la pasa al reusable | El reusable solo aceptará la URL aprobada; si difiere, fallará |
| `BACKUP_SIGNING_PUBLIC_KEY_SHA256` | `4011dd69e227bfcf6f39b3f44b1ad499d2a582c9f3eed93d8896e61b7485ce96` | SHA-256 del DER de `config/backup-signing-public-key.pem` | **No** como variable de repo; la huella está fijada en el reusable y Guardian | No cambia la clave que realmente se acepta |
| `BACKUP_STORAGE_BRANCH` | `backups-signed-latest-30` | Nombre elegido para la rama que guarda las cajas cifradas | **No**; está fijada en reusable, Guardian y pruebas | No cambia la rama real |
| `BACKUP_TIMEOUT_MINUTES` | `120` | Tiempo máximo permitido al job de backup | **No**; `timeout-minutes: 120` está en el reusable | No cambia el timeout real |
| `BACKUP_TIMEZONE` | `Europe/Madrid` | Zona usada para decidir el día y la hora del backup | **No** en GitHub; reusable y Edge Function tienen su propia configuración | No cambia la hora real |
| `EXPECTED_AGE_RECIPIENT_SHA256` | `f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa` | SHA-256 exacto de `BACKUP_AGE_RECIPIENT`, sin salto de línea | **No** como variable; está fijada en reusable y Guardian | No cambia la huella que se valida |
| `OPENBAO_OIDC_AUDIENCE` | `openbao://supabase-backup-signing` | Texto acordado entre GitHub Actions y el signer para el token OIDC | **No** como variable; está fijado en reusable y `fly.toml` | No cambia la audiencia real |

## Aviso importante

Solo estas dos variables gobiernan directamente el workflow actual:

```text
BACKUP_AGE_RECIPIENT
BACKUP_SIGNER_URL
```

Las demás son **copias visibles del contrato**. Son útiles para saber cuál debe ser el valor, pero cambiarlas solas no modifica el código. La matriz de cambios explica todos los sitios que hay que actualizar.

## Cómo calcular la huella del recipient age

En macOS:

```bash
RECIPIENT="$(tr -d '\r\n' < config/age-recipient.txt)"
printf '%s' "$RECIPIENT" | shasum -a 256
```

En Linux o WSL:

```bash
RECIPIENT="$(tr -d '\r\n' < config/age-recipient.txt)"
printf '%s' "$RECIPIENT" | sha256sum
```

Resultado actual esperado:

```text
f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa
```

## Cómo calcular la huella de la clave pública Ed25519

macOS:

```bash
openssl pkey \
  -pubin \
  -in config/backup-signing-public-key.pem \
  -outform DER |
shasum -a 256
```

Linux o WSL:

```bash
openssl pkey \
  -pubin \
  -in config/backup-signing-public-key.pem \
  -outform DER |
sha256sum
```

Resultado actual esperado:

```text
4011dd69e227bfcf6f39b3f44b1ad499d2a582c9f3eed93d8896e61b7485ce96
```
