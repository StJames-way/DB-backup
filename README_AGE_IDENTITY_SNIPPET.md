## Identidad `age` aprobada

La identidad privada no está en el repositorio. El contrato público está en `config/backup-recovery-trust.json`.

```text
Recipient:
age18gt5e7d48tfyhx4552kc5wyp52lt5rf34ag0sat3t4xsrg0fqg8stagvae

SHA-256:
f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa
```

Comprobar una identidad local:

```bash
RECIPIENT="$(age-keygen -y "$HOME/claves/camino-backup-identity.txt")"
printf '%s\n' "$RECIPIENT"
printf '%s' "$RECIPIENT" | shasum -a 256
```

La verificación de identidad `age` es independiente de la doble validación OIDC del flujo de firma.

## Relación con la web de recuperación

La [Backup Recovery PWA](https://stjames-way.github.io/backup-recovery-pwa/) verifica y une el backup cifrado, pero
**nunca debe recibir este archivo de identidad privada**. Carga solo el
manifiesto, la firma, los metadatos públicos y las partes `.part`. El
`.dump.age` resultante se descifra después, fuera del navegador.
