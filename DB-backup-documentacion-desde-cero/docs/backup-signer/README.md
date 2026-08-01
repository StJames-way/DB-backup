# `backup-signer`: instalación y variables

## GitHub Variables

El repositorio `StJames-way/backup-signer` no necesita GitHub Variables.

## GitHub Secrets

Tampoco necesita secretos de despliegue en GitHub. No se guarda `FLY_API_TOKEN`.

## Dónde están entonces los valores

### Valores públicos

Viven en `backup-signer/fly.toml`:

| Nombre | Origen |
|---|---|
| `GITHUB_OIDC_ISSUER` | Valor fijo de GitHub Actions |
| `GITHUB_OIDC_AUDIENCE` | Contrato `openbao://supabase-backup-signing` |
| `ALLOWED_REPOSITORY` | `StJames-way/DB-backup` |
| `ALLOWED_REPOSITORY_ID` | `gh api repos/StJames-way/DB-backup --jq .id` |
| `ALLOWED_REPOSITORY_OWNER_ID` | `gh api repos/StJames-way/DB-backup --jq .owner.id` |
| `ALLOWED_REF` | `refs/heads/main` |
| `ALLOWED_JOB_WORKFLOW_REF` | Ruta del reusable terminada en SHA aprobado `9df9f393517fffddca9e4bb7264211010cb0912b` |
| `ALLOWED_CALLER_WORKFLOW_REF` | Caller en `refs/heads/main` |
| `ALLOWED_EVENTS` | `workflow_dispatch,repository_dispatch` |
| `OPENBAO_ADDR` | `https://camino-openbao.internal:8200` |
| `OPENBAO_CA_FILE` | `/etc/ssl/certs/camino-openbao-ca.pem` |
| `OPENBAO_AUTH_MOUNT` | `approle-backup` |
| `OPENBAO_TRANSIT_MOUNT` | `transit-backup` |
| `OPENBAO_KEY_NAME` | `supabase-backup-manifest` |

### Valores secretos

Solo en Fly Secrets:

```text
OPENBAO_ROLE_ID
OPENBAO_SECRET_ID
```

Comprobar sin mostrar valores:

```bash
fly secrets list \
  --app camino-backup-signer
```

Debe haber exactamente esos dos secretos en estado `Deployed`.

## Actualizar el SHA autorizado

1. Obtén el SHA del commit aprobado de `DB-backup` que contiene reusable/tools/config.
2. Cambia `ALLOWED_JOB_WORKFLOW_REF` en `fly.toml`.
3. Fusiona y pasa CI de signer.
4. Despliega desde Mac/WSL.
5. Solo después cambia el caller de `DB-backup` para usar ese mismo SHA.
