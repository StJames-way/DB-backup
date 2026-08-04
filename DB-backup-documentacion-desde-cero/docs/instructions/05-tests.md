# Pruebas del sistema

## Estáticas

```bash
python3 -m compileall tools/backup
node --check backup-signer-cloudflare/worker/src/index.js
python3 -m pytest -q   # en repo backup-signer
```

Guardian debe rechazar:

- `@main` en reusable;
- hashes cero o desalineados;
- URL signer directa en vez de gateway;
- ausencia de CA/verify-full;
- cambios de clave pública sin huella;
- permisos OIDC insuficientes.

## Contrato Supabase

```sql
SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Resultado `t`.

## Contrato Worker

| Prueba | Esperado |
|---|---|
| `GET /healthz` | 200 |
| `GET /readyz` sin token | 401 |
| `POST /v1/sign` sin OIDC | 401 |
| JWT inválido | 403 |
| JWKS indisponible | 503, nunca bypass |
| cuerpo grande | 413 |
| rate limit | 429 |

## Contrato signer

| Prueba | Esperado |
|---|---|
| llamada directa sin gateway token | 403 |
| gateway token válido + OIDC inválido | 403 |
| manifest provenance diferente | 403 |
| OpenBao no disponible | 502/503 según endpoint |
| firma válida | 200 + signature/key_version/digest |

## E2E

El run de referencia `30878970809` terminó `success`. Para cada cambio:

1. tail Worker;
2. logs signer;
3. lanzar workflow;
4. confirmar `manifest_signed`;
5. comprobar partes, manifest, sig y sig metadata;
6. verificar que la máquina vuelve a `stopped`.

## Recovery

Ninguna suite sustituye al restore real. Sigue `docs/recovery-drill.md`.
