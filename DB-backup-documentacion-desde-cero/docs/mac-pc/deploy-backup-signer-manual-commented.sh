#!/usr/bin/env bash
set -euo pipefail

# Uso seguro, ejecutado desde el repo backup-signer.
APP="${SIGNER_APP:-camino-backup-signer}"

# 1. Nunca imprime secretos. Comprueba solo sus nombres.
fly secrets list -a "$APP"

# 2. La escala a cero es obligatoria.
grep -nE 'internal_port|auto_stop_machines|auto_start_machines|min_machines_running' fly.toml

grep -Eq 'min_machines_running[[:space:]]*=[[:space:]]*0' fly.toml || exit 1

# 3. Tests y configuración.
python3 -m pytest -q
fly config validate

# 4. Despliegue.
fly deploy -a "$APP"

# 5. No libera IPs automáticamente. Hazlo solo tras canario y revisión.
fly ips list -a "$APP"
