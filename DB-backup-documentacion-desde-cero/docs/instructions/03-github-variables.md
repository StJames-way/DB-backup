# Variables, secretos y trust anchors

## GitHub Actions

### Variables

```text
BACKUP_AGE_RECIPIENT=age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae
BACKUP_SIGNER_URL=https://camino-backup-gateway.santiago-way.workers.dev
```

### Secret

```text
SUPABASE_DB_URL
```

No necesita secretos de OpenBao ni Cloudflare.

## Worker

### Variables no secretas

```text
GITHUB_OIDC_AUDIENCE=openbao://supabase-backup-signing
JWT_LEEWAY_SECONDS=30
ALLOWED_REPOSITORY=StJames-way/DB-backup
ALLOWED_REPOSITORY_ID=1283131929
ALLOWED_REPOSITORY_OWNER_ID=297665544
ALLOWED_REF=refs/heads/main
ALLOWED_CALLER_WORKFLOW_REF=StJames-way/DB-backup/.github/workflows/supabase-backup-dispatch.yml@refs/heads/main
ALLOWED_JOB_WORKFLOW_REF=StJames-way/DB-backup/.github/workflows/supabase-age-openbao-reusable.yml@9c1562857b371396e478fe078dd1ace772a93abc
ALLOWED_JOB_WORKFLOW_SHA=9c1562857b371396e478fe078dd1ace772a93abc
ALLOWED_EVENTS=workflow_dispatch,repository_dispatch
```

### Secrets

```text
BACKUP_GATEWAY_TOKEN
BACKUP_HEALTH_TOKEN
```

## Signer Fly

### Variables/configuración

```text
GITHUB_OIDC_ISSUER=https://token.actions.githubusercontent.com
GITHUB_OIDC_AUDIENCE=openbao://supabase-backup-signing
ALLOWED_REPOSITORY=StJames-way/DB-backup
ALLOWED_REPOSITORY_ID=1283131929
ALLOWED_REPOSITORY_OWNER_ID=297665544
ALLOWED_REF=refs/heads/main
ALLOWED_JOB_WORKFLOW_REF=...@9c1562857b371396e478fe078dd1ace772a93abc
ALLOWED_CALLER_WORKFLOW_REF=...@refs/heads/main
OPENBAO_AUTH_MOUNT=approle-backup
OPENBAO_TRANSIT_MOUNT=transit-backup
OPENBAO_KEY_NAME=supabase-backup-manifest
```

### Secrets

```text
OPENBAO_ADDR
OPENBAO_ROLE_ID
OPENBAO_SECRET_ID
BACKUP_GATEWAY_TOKEN
```

## Tunnel Fly

```text
TUNNEL_TOKEN
```

## Edge Function

```text
GITHUB_BACKUP_DISPATCH_TOKEN
GITHUB_BACKUP_REPOSITORY_OWNER
GITHUB_BACKUP_REPOSITORY
BACKUP_AGE_RECIPIENT
SUPABASE_BACKUP_TRIGGER_SECRET
```

## Trust anchors versionados

```text
Age recipient SHA-256:             f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa
Signing public key DER SHA-256:    4011dd69e227bfcf6f39b3f44b1ad499d2a582c9f3eed93d8896e61b7485ce96
Supabase CA DER SHA-256:           807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa
Gateway URL SHA-256:               b8863d62b3e1202b604de3b499b9e4e99751259c68e4a706b72c0a98e6c35553
Reusable SHA:                      9c1562857b371396e478fe078dd1ace772a93abc
```

## Regla

Cualquier cambio en un trust anchor exige actualizar todos sus consumidores y
pasar Guardian + canario + recovery drill cuando corresponda.
