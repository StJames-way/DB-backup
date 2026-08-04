# Checklist GO-LIVE

## Criptografía

- [ ] identidad privada `age` en al menos dos soportes offline
- [ ] recipient público y SHA-256 alineados
- [ ] clave Transit Ed25519 no exportable
- [ ] clave pública y huella DER alineadas
- [ ] CA Supabase y huella DER alineadas

## Supabase

- [ ] `backup_reader` LOGIN, connlimit 10 y sin permisos de escritura
- [ ] grants a todos los schemas necesarios
- [ ] usuario pooler incluye project ref
- [ ] `verify-full` probado localmente
- [ ] `pg_stat_ssl` devuelve `t`
- [ ] Edge Function protegida por trigger secret
- [ ] PAT dispatch limitado al repo

## GitHub

- [ ] `SUPABASE_DB_URL` solo como secret
- [ ] `BACKUP_AGE_RECIPIENT` y gateway URL como variables
- [ ] reusable fijado a SHA completo
- [ ] `id-token: write`
- [ ] concurrency activa
- [ ] branch protection
- [ ] Guardian en verde

## Cloudflare

- [ ] Worker valida firma OIDC y todos los claims
- [ ] JWKS cache/retries desplegados
- [ ] gateway y health tokens separados
- [ ] VPC Service apunta a Flycast:80
- [ ] Tunnel Healthy
- [ ] rate limits configurados
- [ ] `/readyz` protegido despierta desde escala cero

## Fly/OpenBao

- [ ] signer exige gateway token
- [ ] signer revalida OIDC
- [ ] `min_machines_running=0`
- [ ] OpenBao solo por `.internal` HTTPS
- [ ] AppRole de mínimo privilegio
- [ ] no quedan IP públicas en signer, o existe excepción documentada temporal

## E2E y recuperación

- [ ] dos backups consecutivos correctos
- [ ] partes/manifiesto/firma presentes
- [ ] retención validada
- [ ] restore en base aislada correcto
- [ ] acta de recovery drill archivada

## Recovery PWA

- [ ] `https://stjames-way.github.io/backup-recovery-pwa/` o la URL propia abre correctamente.
- [ ] El repositorio/build de la PWA está fijado y registrado.
- [ ] `recovery-trust.json` coincide con `DB-backup`.
- [ ] La PWA verifica un backup completo del proyecto.
- [ ] Rechaza un backup de otro proyecto o trust anchor distinto.
- [ ] No solicita identidad privada `age` ni secretos de infraestructura.
- [ ] Existe copia local/kit CLI para indisponibilidad de GitHub Pages.
- [ ] Se completó además un `pg_restore` en base aislada.
