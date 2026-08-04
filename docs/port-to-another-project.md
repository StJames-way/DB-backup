# Portar el sistema a otro proyecto

## Estrategia

No clones los identificadores del despliegue actual. Reutiliza el diseño y el
código, pero genera nuevas identidades criptográficas, IDs y secretos.

## Inventario que cambia

| Elemento | Acción en el proyecto nuevo |
|---|---|
| repo de backups | crear o elegir uno nuevo |
| repository/owner IDs | consultar con GitHub API |
| project ref Supabase | sustituir |
| pooler host | copiar desde Connect |
| `backup_reader` | crear con password nueva |
| CA Supabase | descargar y fijar huella |
| recipient `age` | generar identidad nueva |
| Transit key | preferiblemente clave nueva |
| AppRole | role y SecretID nuevos |
| signer app | app y Flycast nuevos |
| gateway Worker | nombre/URL nuevos |
| Tunnel | tunnel token y UUID nuevos |
| VPC Service | ID nuevo |
| gateway/health tokens | valores nuevos |
| workflow SHA | commit aprobado nuevo |

## Orden recomendado

1. crear repositorios y protección de `main`;
2. generar identidad `age` offline;
3. crear rol Supabase y probar TLS;
4. configurar OpenBao Transit y AppRole;
5. desplegar signer con entrada todavía controlada;
6. crear Tunnel y VPC Service;
7. configurar Worker con OIDC del repo nuevo;
8. desplegar Worker y probar `/healthz`/`readyz`;
9. configurar GitHub variables/secrets;
10. alinear SHA entre caller, Worker y signer;
11. desplegar Edge Function y cron;
12. ejecutar canario completo;
13. hacer recovery drill;
14. retirar IP pública del signer.

## GitHub IDs

```bash
gh api repos/OWNER/REPO --jq '{repository_id:.id, owner_id:.owner.id}'
```

## URL y huella del gateway

```bash
GATEWAY_URL='https://NUEVO-WORKER.SUBDOMINIO.workers.dev'
printf '%s' "${GATEWAY_URL%/}" | sha256sum
```

Inserta la huella en reusable y Guardian mediante el helper del repo, si está
disponible.

## Identidad `age`

```bash
umask 077
age-keygen -o "$HOME/backup-recovery/NUEVO-age-identity.txt"
age-keygen -y "$HOME/backup-recovery/NUEVO-age-identity.txt"   > config/age-recipient.txt
printf '%s' "$(tr -d '
' < config/age-recipient.txt)" | sha256sum
```

Guarda al menos dos copias offline verificadas de la identidad privada.

## Supabase

Usa `docs/create-backup-reader-role.sql`, aplica grants a todos los schemas y
crea la URL `verify-full`. No copies la password del proyecto actual.

## OpenBao

Puedes usar el mismo cluster si los proyectos pertenecen al mismo dominio de
confianza, pero crea al menos:

- una clave Transit distinta;
- una policy distinta;
- un AppRole distinto;
- nombres que identifiquen el proyecto.

## Cloudflare

El Worker del proyecto nuevo debe tener sus propios:

- allowlists OIDC;
- rate-limit namespaces;
- VPC Service binding;
- `BACKUP_GATEWAY_TOKEN`;
- `BACKUP_HEALTH_TOKEN`.

## Recovery PWA del proyecto nuevo

La URL actual:

```text
https://stjames-way.github.io/backup-recovery-pwa/
```

solo debe validar los trust anchors del proyecto actual. Para otro proyecto crea
y publica una PWA propia a partir de:

```text
https://github.com/StJames-way/backup-recovery-pwa
```

Actualiza al menos:

- repositorio/nombre del sistema de backup;
- recipient `age` y SHA-256;
- clave pública Ed25519 y huella DER;
- `recovery-trust.json`;
- schema y versiones admitidas del manifiesto;
- enlaces a la rama de backups y a la guía;
- URL de GitHub Pages y documentación principal.

No copies la identidad privada `age` al repositorio PWA. Antes del go-live, la
PWA nueva debe verificar un backup completo de su propio proyecto y rechazar
un conjunto del proyecto anterior.

## Prueba de no contaminación

Antes del go-live, confirma que el token OIDC del proyecto A es rechazado por
el Worker y signer del proyecto B. Confirma también que el recipient `age` de A
no puede descifrar backups de B.

## Plantilla de sustituciones

```text
CURRENT_REPO=OWNER/REPO
CURRENT_PROJECT_REF=...
CURRENT_POOLER_HOST=...
CURRENT_GATEWAY_URL=...
CURRENT_SIGNER_APP=...
CURRENT_TUNNEL_APP=...
CURRENT_VPC_SERVICE_ID=...
CURRENT_TUNNEL_ID=...
CURRENT_AGE_RECIPIENT=...
CURRENT_AGE_SHA256=...
CURRENT_SIGNING_KEY_SHA256=...
CURRENT_SUPABASE_CA_SHA256=...
CURRENT_REUSABLE_SHA=...
```

No declares el proyecto listo hasta completar la checklist GO-LIVE.
