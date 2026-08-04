# Documentación exportable del backup

Este directorio es una copia autocontenida de la documentación canónica de
`docs/`. Incluye arquitectura, instalación, pruebas, recuperación, scripts de
auditoría y plantillas para Cloudflare/Fly/Supabase.

Ejecuta `install-docs-into-repo.sh /ruta/a/DB-backup` para instalarla.

## Web de recuperación

La interfaz oficial está en:

```text
https://stjames-way.github.io/backup-recovery-pwa/
```

Código fuente:

```text
https://github.com/StJames-way/backup-recovery-pwa
```

Verifica y une localmente el backup cifrado. No recibe la identidad privada
`age`, no descifra y no ejecuta `pg_restore`. Consulta
`docs/recovery/RECOVERY_PWA.md`.
