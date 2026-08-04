# Runbook de operaciones

## Ejecución manual

```bash
REPO='StJames-way/DB-backup'
gh workflow run supabase-backup-dispatch.yml --repo "$REPO"
sleep 8
RUN_ID="$(gh run list --repo "$REPO"   --workflow supabase-backup-dispatch.yml   --event workflow_dispatch --limit 1   --json databaseId --jq '.[0].databaseId')"
echo "RUN_ID=$RUN_ID"
gh run watch "$RUN_ID" --repo "$REPO" --compact --exit-status
```

## Comprobar artefactos

```bash
gh api 'repos/StJames-way/DB-backup/contents/manifests?ref=backups-signed-latest-30'   --jq '.[].name' | sort | tail

gh api 'repos/StJames-way/DB-backup/contents/signatures?ref=backups-signed-latest-30'   --jq '.[].name' | sort | tail

gh api 'repos/StJames-way/DB-backup/contents/encrypted_backups?ref=backups-signed-latest-30'   --jq '.[].name' | sort | tail
```

## Logs coordinados

Terminal 1:

```bash
cd backup-signer-cloudflare/worker
npx wrangler tail camino-backup-gateway --format pretty
```

Terminal 2:

```bash
fly logs -a camino-backup-signer
```

Terminal 3:

```bash
fly logs -a camino-backup-tunnel
```

Terminal 4: lanza GitHub.

## Readiness desde escala cero

```bash
fly machine list -a camino-backup-signer

GATEWAY='https://camino-backup-gateway.santiago-way.workers.dev'
HEALTH_TOKEN="$(cat /tmp/backup-health-token)"

for ATTEMPT in $(seq 1 20); do
  CODE="$(curl -sS --connect-timeout 10 --max-time 20     -o /tmp/backup-readyz.json -w '%{http_code}'     -H "Authorization: Bearer $HEALTH_TOKEN"     "$GATEWAY/readyz" || true)"
  printf 'Intento %02d: HTTP %s — ' "$ATTEMPT" "$CODE"
  cat /tmp/backup-readyz.json 2>/dev/null || true
  printf '
'
  [ "$CODE" = 200 ] && break
  sleep 4
done
```

## Smoke test de la Recovery PWA

Aplicación:

```text
https://stjames-way.github.io/backup-recovery-pwa/
```

Después de cambiar el formato del manifiesto, recipient `age`, clave pública,
trust JSON o build de la PWA:

1. usa un backup real conocido de `backups-signed-latest-30`;
2. carga carpeta completa en la PWA;
3. exige firma, partes y hash final correctos;
4. genera el kit de terminal;
5. registra el commit de ambas ramas/repositorios;
6. verifica que nunca se solicita la identidad privada.

Una caída de la web no debe bloquear la recuperación: conserva un clon/release
local de `backup-recovery-pwa` y los scripts CLI.

## Rotación de la contraseña DB

1. Genera una contraseña aleatoria fuera del repositorio.
2. `ALTER ROLE backup_reader PASSWORD '...'` en SQL Editor.
3. Construye una URL con password codificada.
4. Prueba localmente con `verify-full`.
5. Actualiza `SUPABASE_DB_URL`.
6. Ejecuta un canario.
7. Destruye notas temporales.

## Rotación del gateway token

1. Genera un valor nuevo.
2. Actualízalo primero en Fly signer.
3. Actualízalo inmediatamente en Cloudflare Worker.
4. Ejecuta `/readyz` y un canario.
5. Elimina el valor temporal local.

La ventana entre ambos cambios puede producir `403`, pero no una autorización
indebida.

## Rotación de la identidad `age`

Es una migración de contrato:

1. genera nueva identidad offline;
2. conserva la antigua mientras existan backups cifrados con ella;
3. cambia `config/age-recipient.txt` y trust JSON;
4. actualiza variable GitHub y secreto de Edge Function;
5. recalcula SHA en reusable/Guardian;
6. pasa canarios y recovery drill;
7. documenta desde qué fecha usa cada recipient.

## Cambio del reusable

Sigue la cascada descrita en `04-update-cascade.md`. Worker, signer y caller
deben aceptar el mismo SHA exacto antes de cortar.

## Monitorización mínima

- alerta si no hay manifiesto nuevo en 26 horas;
- alerta si el último workflow no es `success`;
- alerta si `/readyz` no recupera en varios intentos;
- revisión mensual de IP públicas de Fly;
- revisión trimestral de grants de `backup_reader`;
- recovery drill periódico.
