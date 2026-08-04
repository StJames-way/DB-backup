# Migración completada: signer detrás de Cloudflare Private Gateway

## Antes

```text
GitHub Actions -> signer público en Fly -> OpenBao
```

## Ahora

```text
GitHub Actions
 -> Cloudflare Worker (verifica OIDC)
 -> Workers VPC Service
 -> Cloudflare Tunnel
 -> Flycast signer (revalida OIDC)
 -> OpenBao Transit
```

## Barreras nuevas

- firma JWT GitHub validada en el borde;
- claims allowlisted por IDs y SHA;
- rate limits y tamaño antes del origen;
- token secreto Worker -> signer;
- acceso operativo por VPC/Tunnel/Flycast;
- JWKS con caché, reintentos y fail-closed;
- readiness protegida que despierta el signer desde escala cero.

## Contrato actual

```text
Gateway:      https://camino-backup-gateway.santiago-way.workers.dev
Gateway SHA:  b8863d62b3e1202b604de3b499b9e4e99751259c68e4a706b72c0a98e6c35553
Reusable SHA: 9c1562857b371396e478fe078dd1ace772a93abc
VPC Service:  019fc7fd-7d2b-7262-93cc-87f29fe2a0fc
Tunnel:       6606305d-934a-404e-9cda-afc36a463946
Flycast:      camino-backup-signer.flycast:80
```

## Pasos de corte

1. desplegar signer con gateway token y Flycast;
2. desplegar Tunnel;
3. crear VPC Service;
4. desplegar Worker con OIDC y secrets;
5. configurar gateway URL y huella en DB-backup;
6. alinear SHA entre Worker, signer y caller;
7. canario completo;
8. probar escala a cero;
9. retirar IP pública del signer;
10. repetir canario y recovery drill.

La guía completa contiene comandos, pruebas y rollback.
