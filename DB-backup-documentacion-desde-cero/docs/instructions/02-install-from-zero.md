# Instalación completa desde cero

## 0. Decide el alcance

Se necesitan cinco piezas de código y tres plataformas:

```text
DB-backup                         GitHub workflows, verificación y almacenamiento
backup-signer                    FastAPI privado en Fly
backup-signer-cloudflare/worker  gateway público con OIDC
backup-signer-cloudflare/tunnel  conector saliente cloudflared en Fly
backup-recovery-pwa                verificación y unión local mediante GitHub Pages

Supabase                         origen y disparador
Cloudflare                       Worker, Tunnel y VPC Service
Fly/OpenBao                      signer privado y firma Transit
```

La identidad privada `age` queda fuera de todas ellas.

## 1. Prerrequisitos locales

Mac:

```bash
brew install age gh flyctl jq openssl@3 postgresql@17 supabase/tap/supabase node
```

Comprueba:

```bash
for TOOL in age age-keygen gh fly jq openssl pg_dump pg_restore psql   supabase node npm; do
  command -v "$TOOL" >/dev/null || echo "FALTA: $TOOL"
done
```

Windows: WSL2 Ubuntu. Linux: instala equivalentes y cliente PostgreSQL 17.

## 2. Repositorios y protección

- crea/usa el repo de backup;
- crea/usa el repo signer;
- guarda Worker/Tunnel en un repo privado o monorepo versionado;
- protege `main`;
- exige revisión para workflows, claves públicas y trust anchors;
- prohíbe force-push en `main` y en la rama de almacenamiento.

## 3. Genera la identidad `age`

```bash
umask 077
mkdir -p "$HOME/backup-recovery"
age-keygen -o "$HOME/backup-recovery/supabase-backup-age-identity.txt"
age-keygen -y "$HOME/backup-recovery/supabase-backup-age-identity.txt"   > config/age-recipient.txt
chmod 600 "$HOME/backup-recovery/supabase-backup-age-identity.txt"
```

Calcula la huella sobre el recipient sin salto final:

```bash
RECIPIENT="$(tr -d '
' < config/age-recipient.txt)"
printf '%s' "$RECIPIENT" | sha256sum
```

Actualiza trust JSON, reusable y Guardian. Conserva dos copias offline.

## 4. Crea `backup_reader`

Abre **Supabase SQL Editor**, no la terminal Zsh. Ejecuta
`docs/create-backup-reader-role.sql`, sustituye password y añade schemas.

Confirma:

```text
rolcanlogin=true
rolconnlimit=10
rolbypassrls=true
```

## 5. Descarga y fija la CA de Supabase

Guarda la CA en:

```text
config/prod-ca-2021.crt
```

Calcula huella DER e insértala en reusable/Guardian. Prueba `verify-full` con el
host exacto del Session pooler.

## 6. Configura `SUPABASE_DB_URL`

```text
postgresql://backup_reader.<PROJECT_REF>:<PASSWORD_URLENCODED>@<POOLER_HOST>:5432/postgres?sslmode=verify-full
```

```bash
printf '%s' "$SUPABASE_DB_URL" |
gh secret set SUPABASE_DB_URL --repo OWNER/REPO
```

## 7. Prepara OpenBao

Nombres actuales de referencia:

```text
Transit mount: transit-backup
Transit key:   supabase-backup-manifest
AppRole mount: approle-backup
Role:          backup-signer-gateway
Policy:        backup-signer-gateway
```

```bash
bao secrets enable -path=transit-backup transit || true
bao write transit-backup/keys/supabase-backup-manifest   type=ed25519 exportable=false allow_plaintext_backup=false

cat >/tmp/backup-signer-gateway.hcl <<'EOF'
path "transit-backup/sign/supabase-backup-manifest" {
  capabilities = ["update"]
}
EOF
bao policy write backup-signer-gateway /tmp/backup-signer-gateway.hcl
rm -f /tmp/backup-signer-gateway.hcl

bao auth enable -path=approle-backup approle || true
bao write auth/approle-backup/role/backup-signer-gateway   token_policies=backup-signer-gateway   token_no_default_policy=true   token_ttl=120s token_max_ttl=120s token_num_uses=1   secret_id_num_uses=0 local_secret_ids=true
```

Exporta la pública Transit al repo y calcula su huella DER.

## 8. Configura el signer

Fly secrets:

```text
OPENBAO_ADDR=https://<OPENBAO_APP>.internal:8200
OPENBAO_ROLE_ID
OPENBAO_SECRET_ID
BACKUP_GATEWAY_TOKEN
```

`fly.toml` debe usar:

```toml
[http_service]
internal_port = 8080
force_https = false
auto_stop_machines = "stop"
auto_start_machines = true
min_machines_running = 0
```

Configura allowlists OIDC con el repo nuevo y el SHA aprobado.

Despliega sin retirar todavía IP públicas:

```bash
fly deploy -a <SIGNER_APP>
fly ips allocate-v6 --private -a <SIGNER_APP>
```

## 9. Crea el Tunnel

En Cloudflare `Workers VPC -> Tunnels`, crea un túnel y copia su token.

```bash
cd backup-signer-cloudflare/tunnel-fly
fly apps create <TUNNEL_APP>
fly secrets set -a <TUNNEL_APP> TUNNEL_TOKEN='<TOKEN>'
fly deploy -a <TUNNEL_APP>
fly logs -a <TUNNEL_APP>
```

Debe aparecer Connected/Healthy y no tener servicio de entrada.

## 10. Crea VPC Service

```bash
npx wrangler vpc service create <SERVICE_NAME>   --type http   --tunnel-id '<TUNNEL_UUID>'   --hostname '<SIGNER_APP>.flycast'   --http-port 80
```

Inserta `service_id` en `wrangler.toml`.

## 11. Configura Worker y OIDC

Consulta IDs de GitHub:

```bash
gh api repos/OWNER/REPO --jq '{repository_id:.id, owner_id:.owner.id}'
```

Configura todos los `ALLOWED_*`, la audiencia y SHA. Carga dos secretos:

```text
BACKUP_GATEWAY_TOKEN  mismo que signer
BACKUP_HEALTH_TOKEN   distinto
```

Valida y despliega:

```bash
npm install
npm run check
npx wrangler deploy --secrets-file /tmp/backup-worker-secrets.env
```

## 12. Configura GitHub

Variables:

```text
BACKUP_AGE_RECIPIENT
BACKUP_SIGNER_URL
```

Secret:

```text
SUPABASE_DB_URL
```

Fija la huella de URL del gateway en reusable/Guardian y alinea el SHA en:

- caller;
- Worker;
- signer.

## 13. Configura la Edge Function

Nombre actual:

```text
trigger-supabase-backup
```

Secretos:

```text
GITHUB_BACKUP_DISPATCH_TOKEN
GITHUB_BACKUP_REPOSITORY_OWNER
GITHUB_BACKUP_REPOSITORY
BACKUP_AGE_RECIPIENT
SUPABASE_BACKUP_TRIGGER_SECRET
```

```bash
supabase functions deploy trigger-supabase-backup   --project-ref <PROJECT_REF> --no-verify-jwt
```

La función sigue exigiendo su propio Bearer secret.

## 14. Programa cron

Guarda el trigger secret en Supabase Vault y usa `pg_cron + pg_net`. No guardes
el PAT de GitHub en SQL.

## 15. Pruebas antes del corte

1. conexión local `backup_reader`;
2. `pg_stat_ssl = t`;
3. `/healthz` Worker 200;
4. firma anónima 401;
5. `/readyz` protegido 200 desde máquinas paradas;
6. canario GitHub success;
7. partes/manifiesto/firma presentes;
8. recovery drill en DB aislada;
9. dos canarios seguidos;
10. retirar IPs públicas del signer y repetir canario.

## 16. Evidencia de la instalación actual

El despliegue actual completó el run `30878970809` y publicó
`database_backup_2026-08-04_06-53-27` con partes `aaa` y `aab`.

## Publicar la Recovery PWA

Despliega una copia propia de [https://github.com/StJames-way/backup-recovery-pwa](https://github.com/StJames-way/backup-recovery-pwa), actualiza recipient,
huellas, clave pública y `recovery-trust.json`, habilita GitHub Pages y prueba
un backup real. La identidad privada `age` nunca entra en ese repositorio.
