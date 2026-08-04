# Índice de documentación

## Empezar

1. `GUIA_BACKUP_DESDE_CERO.md`
2. `current-deployment-contract.md`
3. `backup-architecture.md`

## Instalar y portar

- `deploy-from-zero.md`
- `create-backup-reader-role.sql`
- `configure-supabase-verified-tls.md`
- `cloudflare-private-gateway.md`
- `port-to-another-project.md`

## Operar

- `operations-runbook.md`
- `troubleshooting.md`
- `security-boundaries.md`

## Recuperar

- `disaster-recovery.md`
- `recovery-drill.md`
- `recovery/AGE_IDENTITY_CHECK.md`

`docs/` es la fuente canónica. El directorio
`DB-backup-documentacion-desde-cero/` es una copia exportable que debe
regenerarse desde esta fuente para evitar divergencias.

## Recuperación asistida

- Web: [https://stjames-way.github.io/backup-recovery-pwa/](https://stjames-way.github.io/backup-recovery-pwa/)
- Código: [https://github.com/StJames-way/backup-recovery-pwa](https://github.com/StJames-way/backup-recovery-pwa)
- Manual: `recovery/RECOVERY_PWA.md`

La PWA verifica y une localmente; la identidad privada `age`, el descifrado y
`pg_restore` permanecen fuera del navegador.
