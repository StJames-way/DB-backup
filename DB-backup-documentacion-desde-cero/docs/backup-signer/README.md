# `backup-signer`: instalación privada y variables

## Papel

El signer es una segunda barrera después de Cloudflare. No confía en que el
Worker haya validado correctamente: exige gateway token, revalida OIDC,
compara provenance y firma mediante OpenBao.

## Configuración pública

```text
GITHUB_OIDC_ISSUER=https://token.actions.githubusercontent.com
GITHUB_OIDC_AUDIENCE=openbao://supabase-backup-signing
ALLOWED_REPOSITORY=StJames-way/DB-backup
ALLOWED_REPOSITORY_ID=1283131929
ALLOWED_REPOSITORY_OWNER_ID=297665544
ALLOWED_REF=refs/heads/main
ALLOWED_JOB_WORKFLOW_REF=...@9c1562857b371396e478fe078dd1ace772a93abc
ALLOWED_CALLER_WORKFLOW_REF=...@refs/heads/main
ALLOWED_EVENTS=workflow_dispatch,repository_dispatch
OPENBAO_CA_FILE=/etc/ssl/certs/camino-openbao-ca.pem
OPENBAO_AUTH_MOUNT=approle-backup
OPENBAO_TRANSIT_MOUNT=transit-backup
OPENBAO_KEY_NAME=supabase-backup-manifest
```

## Secrets Fly

```text
OPENBAO_ADDR
OPENBAO_ROLE_ID
OPENBAO_SECRET_ID
BACKUP_GATEWAY_TOKEN
```

## Flycast y escala a cero

```toml
[http_service]
internal_port = 8080
force_https = false
auto_stop_machines = "stop"
auto_start_machines = true
min_machines_running = 0
```

`force_https=false` es necesario porque el salto VPC/Flycast interno es HTTP
sobre la red privada. La conexión signer -> OpenBao sí es HTTPS.

## Entrada pública

La ruta deseada no usa `*.fly.dev`. Después del canario, libera IPs públicas.
El middleware seguiría rechazando peticiones sin gateway token, pero la
reducción de superficie requiere cerrar también la entrada de red.
