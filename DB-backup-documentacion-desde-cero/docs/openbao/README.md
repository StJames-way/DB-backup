# OpenBao para el backup

## Principio

No se crea un OpenBao público ni uno dentro de GitHub. El signer usa el cluster
principal por DNS privado Fly y TLS con CA propia.

## Policy mínima

```hcl
path "transit-backup/sign/supabase-backup-manifest" {
  capabilities = ["update"]
}
```

El signer no puede leer, exportar, rotar ni borrar la clave, ni acceder a otros
paths.

## AppRole

```text
Mount: approle-backup/
Role:  backup-signer-gateway
Token: 120 s, un uso, sin default policy
```

## Clave

```text
Mount:      transit-backup/
Key:        supabase-backup-manifest
Type:       ed25519
Exportable: false
Sign:       true
```

## Salud

`/readyz` consulta `sys/health` con códigos de active/standby permitidos. No
consume un token AppRole. La firma sí realiza login y usa el token de un uso.

## Rotación

Conserva las claves públicas de versiones históricas o una política clara de
verificación. No destruyas una versión de firma mientras haya backups que la
referencien.
