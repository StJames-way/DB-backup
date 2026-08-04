# DB-backup — backup cifrado, firmado y con doble verificación OIDC

Este repositorio crea backups completos de Supabase PostgreSQL y los almacena
cifrados en una rama separada. La arquitectura actual añade Cloudflare como
primera barrera de identidad: el Worker verifica el OIDC de GitHub y solo
entonces usa VPC Service + Tunnel + Flycast para alcanzar el signer. El signer
revalida OIDC y OpenBao Transit firma el manifiesto.

## Estado validado

```text
Run GitHub:       30878970809
Resultado:        success
Backup:           database_backup_2026-08-04_06-53-27
Partes:           aaa, aab
TLS Supabase:     verify-full
Signer:           escala a cero
OIDC:             Worker + signer
Firma:            OpenBao Ed25519
```

## Flujo

```text
Supabase --TLS verify-full--> GitHub Actions --age--> rama de backups
                                      |
                                      +--OIDC + manifest--> Cloudflare Worker
                                                             |
                                                             +--VPC/Tunnel--> Flycast signer
                                                                                |
                                                                                +--> OpenBao Transit
```

## Documentación

- [Guía completa](docs/GUIA_BACKUP_DESDE_CERO.md)
- [Arquitectura](docs/backup-architecture.md)
- [Contrato actual](docs/current-deployment-contract.md)
- [TLS Supabase](docs/configure-supabase-verified-tls.md)
- [Cloudflare privado](docs/cloudflare-private-gateway.md)
- [Operaciones](docs/operations-runbook.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Portar a otro proyecto](docs/port-to-another-project.md)
- [Restauración](docs/disaster-recovery.md)
- [Recovery drill](docs/recovery-drill.md)
- [Fronteras de seguridad](docs/security-boundaries.md)

## Identidad `age` aprobada

```text
Recipient: age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae
SHA-256:   f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa
```

La identidad privada no está en el repositorio.

## Artefactos del backup

```text
encrypted_backups/<base>.dump.age.aaa.part
manifests/<base>.json
signatures/<base>.sig
signatures/<base>.json
```

Los dos JSON tienen el mismo basename pero directorios distintos; no existe
colisión.

## Estado operativo frente a estado de recuperación

La creación, cifrado, firma, verificación y publicación están en verde. Para
afirmar que la recuperación completa está validada debe existir un restore de
prueba reciente en una base aislada. También debe verificarse que el signer no
conserve IPs públicas antiguas.
