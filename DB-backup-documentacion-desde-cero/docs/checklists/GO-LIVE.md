# Checklist antes de considerar el sistema terminado

- [ ] `SUPABASE_DB_URL` está solo en GitHub Secret.
- [ ] La identidad privada `age` está offline y hay una copia de recuperación segura.
- [ ] `config/age-recipient.txt` contiene solo la pública.
- [ ] La huella age es `f59fd599322f109270cfa7fd614e38b8eb7d5ca823c0443f8f0d55651e4b31aa`.
- [ ] La huella pública Ed25519 es `4011dd69e227bfcf6f39b3f44b1ad499d2a582c9f3eed93d8896e61b7485ce96`.
- [ ] Caller y signer usan el mismo SHA reusable `9df9f393517fffddca9e4bb7264211010cb0912b`.
- [ ] `backup-signer` tiene exactamente dos Fly Secrets.
- [ ] `/healthz` devuelve `ok`.
- [ ] `/readyz` devuelve `ready`.
- [ ] `Guardian / static contract` está verde.
- [ ] `Guardian / production canary` está verde.
- [ ] E2E desde `trigger-github-backup` está verde.
- [ ] Existe un commit nuevo en `backups-signed-latest-30`.
- [ ] Existe manifiesto, firma y todas las partes.
- [ ] Se realizó una restauración aislada.
