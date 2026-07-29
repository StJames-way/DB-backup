# Arquitectura del backup firmado

## Flujo

1. Un runner efímero `ubuntu-24.04` de GitHub Actions conecta con Supabase.
2. Ejecuta `pg_dump --format=custom`.
3. Calcula SHA-256 del dump plano.
4. Cifra el dump con el recipient público de `age`.
5. Divide el cifrado en partes de 90 MiB.
6. Construye un manifiesto JSON determinista.
7. Solicita un token OIDC a GitHub con audiencia
   `openbao://supabase-backup-signing`.
8. Envía el manifiesto y el token al servicio público `backup-signer`.
9. `backup-signer` verifica el token, canonicaliza el manifiesto y solicita
   una firma Ed25519 a OpenBao Transit por la red privada de Fly.
10. GitHub verifica localmente la firma con la clave pública.
11. Publica partes, manifiesto y firma en `backups-signed-latest-30`.

## Límites de confianza

- GitHub contiene `SUPABASE_DB_URL` y procesa temporalmente el dump plano.
- GitHub no contiene credenciales de OpenBao.
- El firmador no recibe el dump ni la URL de Supabase.
- OpenBao no recibe el dump; solo los bytes canónicos del manifiesto.
- La clave privada Ed25519 permanece no exportable en Transit.

## Autorización OIDC

El firmador debe validar como mínimo:

- emisor y audiencia;
- expiración y algoritmo JWT;
- `repository` y `repository_id`;
- `repository_owner_id`;
- `ref == refs/heads/main`;
- `job_workflow_ref` fijado al SHA aprobado;
- `workflow_ref` del caller;
- `event_name`;
- `runner_environment == github-hosted`.

## Canonicalización

La firma se realiza sobre:

```python
json.dumps(
    manifest,
    sort_keys=True,
    separators=(",", ":"),
    ensure_ascii=False,
).encode("utf-8")
```

No se firma el cuerpo HTTP original ni un JSON con formato arbitrario.


## Disparo desde Supabase

La Edge Function:

```text
supabase/functions/trigger-supabase-backup/index.ts
```

no accede a la base ni ejecuta `pg_dump`. Envía un `repository_dispatch`
autenticado a GitHub e incluye la huella SHA-256 del recipient `age`.
El workflow vuelve a calcular esa huella y rechaza cualquier discrepancia.
