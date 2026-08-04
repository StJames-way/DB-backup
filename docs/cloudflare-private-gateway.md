# Cloudflare Backup Gateway privado

## Qué añade Cloudflare

La arquitectura anterior enviaba el OIDC directamente al signer. La actual
incorpora una barrera de borde que **verifica criptográficamente el OIDC antes
de usar la red privada hacia Fly**.

```text
GitHub Actions
  -> Worker público /v1/sign
  -> validación OIDC + rate limits + tamaño
  -> Workers VPC Service
  -> Cloudflare Tunnel
  -> Flycast
  -> signer
  -> OpenBao
```

## Componentes

### Worker `camino-backup-gateway`

Endpoints:

```text
GET  /healthz
GET  /readyz   (Bearer BACKUP_HEALTH_TOKEN)
POST /v1/sign  (Bearer GitHub OIDC)
```

El Worker nunca recibe el dump. Reenvía exclusivamente el manifiesto.

### VPC Service

Despliegue actual:

```text
ID:       019fc7fd-7d2b-7262-93cc-87f29fe2a0fc
Type:     http
Hostname: camino-backup-signer.flycast
Port:     80
Tunnel:   6606305d-934a-404e-9cda-afc36a463946
```

Para otra cuenta se crea uno nuevo y se sustituye el `service_id`.

### Tunnel connector

La app `camino-backup-tunnel` ejecuta `cloudflared` y no expone servicios de
entrada. Solo abre conexiones salientes a Cloudflare.

### Signer

Fly Proxy recibe tráfico por Flycast y despierta una máquina cuando está
parada. El signer exige además el secreto compartido `BACKUP_GATEWAY_TOKEN`.

## Configuración OIDC del Worker

Variables no secretas:

```text
GITHUB_OIDC_AUDIENCE
JWT_LEEWAY_SECONDS
ALLOWED_REPOSITORY
ALLOWED_REPOSITORY_ID
ALLOWED_REPOSITORY_OWNER_ID
ALLOWED_REF
ALLOWED_CALLER_WORKFLOW_REF
ALLOWED_JOB_WORKFLOW_REF
ALLOWED_JOB_WORKFLOW_SHA
ALLOWED_EVENTS
```

Secretos:

```text
BACKUP_GATEWAY_TOKEN
BACKUP_HEALTH_TOKEN
```

## JWKS y fail-closed

El Worker descarga:

```text
https://token.actions.githubusercontent.com/.well-known/jwks
```

Si las claves no están disponibles después de los reintentos, responde `503`
y no reenvía la petición. Si el JWT es inválido o sus claims no están
permitidos, responde `403`.

Nunca debe existir un fallback de “aceptar sin verificar”.

## Despliegue resumido

```bash
cd backup-signer-cloudflare/worker
npm install
npx wrangler login
npm run check
npx wrangler deploy --secrets-file /tmp/backup-worker-secrets.env
```

El archivo temporal contiene:

```text
BACKUP_GATEWAY_TOKEN=<mismo secreto que Fly>
BACKUP_HEALTH_TOKEN=<secreto independiente>
```

Bórralo después del despliegue.

## Crear VPC Service

```bash
npx wrangler vpc service create <NOMBRE>   --type http   --tunnel-id '<TUNNEL_UUID>'   --hostname '<SIGNER_APP>.flycast'   --http-port 80
```

Comprueba:

```bash
npx wrangler vpc service get '<SERVICE_ID>'
```

## Pruebas

### Vida básica

```bash
curl -i 'https://camino-backup-gateway.santiago-way.workers.dev/healthz'
```

### Readiness profunda

```bash
curl -i   -H "Authorization: Bearer $(cat /tmp/backup-health-token)"   'https://camino-backup-gateway.santiago-way.workers.dev/readyz'
```

Debe despertar el signer desde escala cero y devolver `200`.

### Firma anónima

```bash
curl -i -X POST   -H 'Content-Type: application/json'   --data '{"manifest":{}}'   'https://camino-backup-gateway.santiago-way.workers.dev/v1/sign'
```

Debe devolver `401`.

## Logs

```bash
npx wrangler tail camino-backup-gateway --format pretty
fly logs -a camino-backup-signer
fly logs -a camino-backup-tunnel
```

Códigos relevantes:

| Log | Significado |
|---|---|
| `github_oidc_rejected` | JWT o claims no autorizados |
| `github_oidc_verifier_unavailable` | no fue posible verificar JWKS; fail-closed |
| `github_jwks_fetch_failed` | fallo de red/DNS/timeout al descargar JWKS |
| `signer_upstream_exception` | Worker no alcanzó VPC/Tunnel/Flycast |
| `readyz_upstream_not_ready` | signer u OpenBao todavía no están listos |

## Escala a cero

No cambies `min_machines_running` a 1 para ocultar problemas de arranque. La
prueba correcta es:

```text
máquinas stopped -> /readyz -> Flycast arranca -> 200 -> autostop posterior
```

## Retirada de IP pública

Después de dos canarios correctos:

```bash
fly ips list -a camino-backup-signer
fly ips release <PUBLIC_IP> -a camino-backup-signer
```

Conserva la dirección de tipo `private ingress`. Repite el canario tras cada
cambio de red.
