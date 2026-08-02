# Identidad age y contrato público de recuperación

## Datos públicos aprobados

```text
Recipient:
age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae

SHA-256 del recipient:
f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa

Huella SHA-256 DER de la clave pública Ed25519:
4011dd69e227bfcf6f39b3f44b1ad499d2a582c9f3eed93d8896e61b7485ce96
```

Estos valores no son secretos. La identidad privada no se guarda en el
repositorio.

## Comprobar una identidad local

```bash
IDENTITY="$HOME/claves/camino-backup-identity.txt"

RECIPIENT="$(
  age-keygen -y "$IDENTITY"
)"

printf 'Recipient: %s\n' "$RECIPIENT"

printf '%s' "$RECIPIENT" |
shasum -a 256
```

Resultado esperado:

```text
age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae
f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa  -
```

El guion final significa que `shasum` leyó desde entrada estándar. No forma
parte del hash.

## Validar el contrato del repositorio

```bash
python3 tools/backup/validate_recovery_trust.py
```

## Paso para Backup Guardian

```yaml
- name: Validate public recovery trust contract
  run: |
    python3 tools/backup/validate_recovery_trust.py
```

El validador comprueba el recipient, su SHA-256 y la huella DER de la clave
pública. No lee ni necesita la identidad privada.
