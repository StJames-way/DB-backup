# OpenBao para el backup

## No se crea otro OpenBao

Este sistema usa `camino-openbao`, el OpenBao principal.

## Permiso mínimo

El signer solo puede hacer:

```text
update transit-backup/sign/supabase-backup-manifest
```

No puede:

```text
leer la clave
exportarla
cifrar
descifrar
rotarla
borrarla
administrar OpenBao
```

## Identidad

```text
Auth mount: approle-backup/
Role:       backup-signer-gateway
Policy:     backup-signer-gateway
Token:      120 segundos, un solo uso, sin default policy
```

## Clave

```text
Transit mount: transit-backup/
Key:           supabase-backup-manifest
Type:          ed25519
Exportable:    false
Encrypt:       false
Decrypt:       false
Sign:          true
```
