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

## Recuperación asistida en el navegador

> [!IMPORTANT]
> La interfaz recomendada para **verificar y reconstruir el backup cifrado** es
> **[Backup Recovery PWA](https://stjames-way.github.io/backup-recovery-pwa/)**.

| Recurso | Dirección |
|---|---|
| Aplicación publicada | [https://stjames-way.github.io/backup-recovery-pwa/](https://stjames-way.github.io/backup-recovery-pwa/) |
| Código fuente | [https://github.com/StJames-way/backup-recovery-pwa](https://github.com/StJames-way/backup-recovery-pwa) |
| Guía visual PDF | [Abrir guía paso a paso](https://stjames-way.github.io/backup-recovery-pwa/guia-recuperacion-backup-paso-a-paso.pdf) |
| Contrato público desplegado | [backup-recovery-trust.json](https://stjames-way.github.io/backup-recovery-pwa/backup-recovery-trust.json) |

La PWA se publica desde un **repositorio hermano** mediante GitHub Pages. Los
archivos seleccionados permanecen en el ordenador del operador: no se suben a
GitHub Pages ni a una API. La aplicación comprueba:

- el contrato público y el recipient `age` aprobado;
- la huella de la clave pública Ed25519;
- el manifiesto y la firma `.sig` producida mediante OpenBao Transit;
- los metadatos de firma JSON, cuando existen;
- el nombre, orden, tamaño y SHA-256 de cada parte `.part`;
- el SHA-256 final del archivo cifrado `.dump.age`;
- la unión secuencial de las partes o la generación de un kit de terminal.

La PWA **no solicita ni recibe la identidad privada `age`**, no descifra el
dump, no ejecuta `pg_restore` y no sustituye un simulacro de restauración real.
El resultado de la unión sigue siendo un archivo cifrado `.dump.age`.

Uso rápido:

1. descarga o clona la rama `backups-signed-latest-30`;
2. abre la [Backup Recovery PWA](https://stjames-way.github.io/backup-recovery-pwa/);
3. selecciona la carpeta que contiene `manifests/`, `signatures/` y
   `encrypted_backups/`, o carga los archivos manualmente;
4. pulsa **Verificar y unir** o genera el **kit completo de terminal**;
5. descifra después con la identidad privada `age` offline y restaura solo en
   una base aislada.

La explicación completa está en [`docs/recovery-pwa.md`](docs/recovery-pwa.md).

## Documentación

- [Guía completa](docs/GUIA_BACKUP_DESDE_CERO.md)
- [Arquitectura](docs/backup-architecture.md)
- [Contrato actual](docs/current-deployment-contract.md)
- [TLS Supabase](docs/configure-supabase-verified-tls.md)
- [Cloudflare privado](docs/cloudflare-private-gateway.md)
- [Operaciones](docs/operations-runbook.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Portar a otro proyecto](docs/port-to-another-project.md)
- [PWA de recuperación](docs/recovery-pwa.md)
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
