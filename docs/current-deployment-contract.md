# Contrato del despliegue actual

Este archivo registra anclas públicas y nombres operativos del despliegue que
pasó el canario completo el 4 de agosto de 2026. No contiene contraseñas,
tokens, RoleID ni SecretID.

## Evidencia funcional

```text
GitHub run:        30878970809
Resultado:         success
Backup base:       database_backup_2026-08-04_06-53-27
Partes observadas: .aaa.part, .aab.part
Manifiesto:        presente
Firma .sig:        presente
Metadatos firma:   presentes
```

## GitHub

| Campo | Valor actual |
|---|---|
| Repositorio | `StJames-way/DB-backup` |
| Repository ID | `1283131929` |
| Owner ID | `297665544` |
| Caller | `.github/workflows/supabase-backup-dispatch.yml@refs/heads/main` |
| Reusable aprobado | `.github/workflows/supabase-age-openbao-reusable.yml@9c1562857b371396e478fe078dd1ace772a93abc` |
| Rama de almacenamiento | `backups-signed-latest-30` |
| Audiencia OIDC | `openbao://supabase-backup-signing` |

## Supabase

| Campo | Valor actual |
|---|---|
| Project ref | `urfbxknxmzcvgogkixdq` |
| Pooler session host | `aws-0-eu-west-1.pooler.supabase.com` |
| Puerto | `5432` |
| Base | `postgres` |
| Rol | `backup_reader` |
| Usuario pooler | `backup_reader.urfbxknxmzcvgogkixdq` |
| SSL | `verify-full` |
| CA | `config/prod-ca-2021.crt` |
| SHA-256 DER CA | `807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa` |
| Connection limit | `10` |

Configuración de sesión del rol:

```text
idle_session_timeout=5min
idle_in_transaction_session_timeout=2min
lock_timeout=30s
statement_timeout=2h
```

## `age`

```text
Recipient: age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae
SHA-256:   f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa
```

La identidad privada correspondiente queda fuera de todos los servicios.

## Firma

```text
Clave pública SHA-256 DER: 4011dd69e227bfcf6f39b3f44b1ad499d2a582c9f3eed93d8896e61b7485ce96
Transit mount:             transit-backup
Transit key:               supabase-backup-manifest
AppRole mount:             approle-backup
Role:                      backup-signer-gateway
```

## Cloudflare

| Campo | Valor actual |
|---|---|
| Worker | `camino-backup-gateway` |
| URL | `https://camino-backup-gateway.santiago-way.workers.dev` |
| SHA-256 URL normalizada | `b8863d62b3e1202b604de3b499b9e4e99751259c68e4a706b72c0a98e6c35553` |
| VPC Service ID | `019fc7fd-7d2b-7262-93cc-87f29fe2a0fc` |
| Tunnel ID | `6606305d-934a-404e-9cda-afc36a463946` |
| VPC hostname | `camino-backup-signer.flycast` |
| VPC HTTP port | `80` |

Rate limits actuales:

```text
EDGE_RATE_LIMITER:   20 peticiones / 60 s por IP
TOKEN_RATE_LIMITER:   5 peticiones / 60 s por token
ORIGIN_RATE_LIMITER: 60 peticiones / 60 s para firma
READY_RATE_LIMITER:  10 peticiones / 60 s para readiness
```

Secretos del Worker:

```text
BACKUP_GATEWAY_TOKEN
BACKUP_HEALTH_TOKEN
```

## Fly signer

```text
App:                   camino-backup-signer
Flycast hostname:      camino-backup-signer.flycast
Internal port:         8080
Auto start:            true
Auto stop:             stop
Min machines running:  0
OpenBao:               https://camino-openbao.internal:8200
```

Secretos en Fly:

```text
OPENBAO_ADDR
OPENBAO_ROLE_ID
OPENBAO_SECRET_ID
BACKUP_GATEWAY_TOKEN
```

## Fly tunnel

```text
App: camino-backup-tunnel
Secret: TUNNEL_TOKEN
Entrada HTTP: ninguna
Comportamiento: solo conexiones salientes de cloudflared
```

## Variables y secretos de GitHub

### Actions variables

```text
BACKUP_AGE_RECIPIENT=age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae
BACKUP_SIGNER_URL=https://camino-backup-gateway.santiago-way.workers.dev
```

### Actions secrets

```text
SUPABASE_DB_URL
```

Forma esperada, sin mostrar contraseña:

```text
postgresql://backup_reader.urfbxknxmzcvgogkixdq:<PASSWORD_URLENCODED>@aws-0-eu-west-1.pooler.supabase.com:5432/postgres?sslmode=verify-full
```

## Elementos que no se copian a otro proyecto

No copies sin recalcular:

- repository ID y owner ID;
- project ref y host/region del pooler;
- recipient `age` ni su clave privada;
- CA ni su huella;
- clave Transit ni su clave pública;
- Worker URL y su huella;
- VPC Service ID ni Tunnel ID;
- SHA del reusable;
- tokens de gateway, health, tunnel o AppRole.

## Control pendiente de exposición pública

Antes de afirmar que el signer carece de entrada pública, ejecutar:

```bash
fly ips list -a camino-backup-signer
```

Solo debe quedar `private ingress`. Cualquier `public ingress` debe retirarse
tras confirmar dos canarios correctos por la ruta Cloudflare privada.
