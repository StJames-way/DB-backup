# Procedimiento seguro de restauración

Este procedimiento separa dos operaciones:

1. **Verificar y descifrar** el backup sin tocar producción.
2. **Restaurarlo** en una base nueva, vacía y aislada.

Nunca restaures directamente sobre producción para probar un backup.

## 1. Condiciones previas

Usa una estación de recuperación confiable, actualizada y con disco cifrado.
Desconecta sincronizadores automáticos de carpetas y evita directorios
compartidos. No ejecutes el procedimiento desde `/tmp`, Dropbox, iCloud Drive
ni una carpeta indexada por terceros.

Necesitas:

- checkout limpio de `DB-backup`;
- branch `backups-signed-latest-30`;
- clave pública Ed25519 correspondiente al backup;
- identidad privada `age` almacenada fuera de GitHub;
- PostgreSQL client compatible;
- Python con `cryptography`;
- espacio libre superior a dos veces el tamaño total del backup.

La firma acredita el manifiesto. La identidad privada `age` permite descifrar.
Son controles distintos y ambos son obligatorios.

## 2. Descargar una copia inmutable

No trabajes directamente sobre la copia remota. Clona y fija el commit:

```bash
set -euo pipefail
umask 077

git clone --filter=blob:none \
  --branch backups-signed-latest-30 \
  git@github.com:StJames-way/DB-backup.git \
  DB-backup-restore

cd DB-backup-restore
git rev-parse HEAD | tee RESTORE_SOURCE_COMMIT.txt
git status --porcelain
test -z "$(git status --porcelain)"
```

Conserva el SHA en el acta de restauración.

## 3. Elegir el conjunto

```bash
ls -1 manifests/database_backup_*.json
```

Define las rutas del mismo timestamp:

```bash
STAMP="2026-07-29_03-00-00"

MANIFEST="manifests/database_backup_${STAMP}.json"
SIGNATURE="signatures/database_backup_${STAMP}.signature"
PUBLIC_KEY="config/backup-signing-public-key.pem"
AGE_IDENTITY="/VOLUMEN-OFFLINE/backup-age-identity.txt"
```

No copies la identidad privada dentro del repositorio.

## 4. Verificar, reconstruir y descifrar

```bash
python3 tools/backup/restore_backup.py \
  --manifest "$MANIFEST" \
  --signature "$SIGNATURE" \
  --public-key "$PUBLIC_KEY" \
  --age-identity "$AGE_IDENTITY" \
  --output "/VOLUMEN-CIFRADO/restore/database_backup_${STAMP}.dump"
```

El script se detiene ante cualquiera de estos problemas:

- parte ausente;
- tamaño o SHA-256 incorrectos;
- firma inválida;
- cifrado reconstruido distinto;
- identidad `age` incorrecta;
- hash del dump plano distinto;
- archivo que `pg_restore` no puede listar;
- destino preexistente.

No usa `--clean`, no conecta con PostgreSQL y no puede modificar producción.

## 5. Crear un destino aislado

Crea una instancia o base temporal sin conexiones de la aplicación. No uses el
mismo nombre, hostname ni credenciales que producción.

```bash
export RESTORE_DATABASE_URL='postgresql://restore_admin:...@HOST:5432/restore_test'
export DUMP="/VOLUMEN-CIFRADO/restore/database_backup_${STAMP}.dump"

pg_restore --list "$DUMP" > restore.contents.txt
```

Comprueba manualmente que `RESTORE_DATABASE_URL` contiene el host de prueba:

```bash
python3 - <<'PY'
import os
from urllib.parse import urlparse

url = urlparse(os.environ["RESTORE_DATABASE_URL"])
print("Host destino:", url.hostname)
print("Base destino:", url.path.lstrip("/"))

if not url.hostname or url.hostname in {
    "db.PRODUCTION_PROJECT_REF.supabase.co",
    "PRODUCTION_HOST",
}:
    raise SystemExit("Destino de restauración no autorizado")
PY
```

## 6. Restaurar

Para una base nueva y vacía:

```bash
pg_restore \
  --exit-on-error \
  --verbose \
  --no-owner \
  --no-privileges \
  --dbname "$RESTORE_DATABASE_URL" \
  "$DUMP" \
  2>&1 | tee restore.log
```

No uses `--clean` contra producción. En una prueba repetida, elimina y recrea
la base temporal completa en lugar de limpiar objetos selectivamente.

## 7. Validación técnica

Comprueba al menos:

```bash
psql "$RESTORE_DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
select current_database(), current_user, now();

select count(*) as user_tables
from information_schema.tables
where table_schema = 'public'
  and table_type = 'BASE TABLE';

select extname, extversion
from pg_extension
order by extname;

select schemaname, tablename, rowsecurity
from pg_tables
where schemaname = 'public'
order by tablename;

select n.nspname as schema_name,
       p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname;
SQL
```

Después ejecuta las comprobaciones específicas del proyecto:

- migración más reciente presente;
- tablas críticas con volumen razonable;
- RLS habilitado donde corresponda;
- funciones y triggers presentes;
- roles y permisos esperados;
- lectura funcional mediante una cuenta de prueba;
- ausencia de conexión de servicios de producción.

Un backup no se considera recuperable hasta superar una restauración completa.

## 8. Destrucción segura del entorno temporal

Tras documentar el resultado:

1. elimina la instancia/base temporal;
2. elimina el dump plano;
3. desmonta el volumen que contiene la identidad `age`;
4. conserva únicamente el manifiesto, la firma, el commit fuente y el acta;
5. verifica que no quedaron dumps en logs, artifacts o sincronizadores.

En SSD modernos no confíes en `shred`. Guarda el dump solo en almacenamiento
cifrado y destruye el volumen o la clave de cifrado cuando termine la prueba.

## 9. Acta mínima

Registra:

```text
Fecha UTC:
Commit de backups-signed-latest-30:
Manifiesto:
Versión de clave Transit:
Huella de la clave pública:
Operador:
Host/base temporal:
Resultado de verificación:
Resultado de pg_restore:
Comprobaciones funcionales:
Incidencias:
Fecha de destrucción del entorno:
```

## 10. Frecuencia

Realiza una restauración completa al menos una vez al mes y siempre después de:

- cambiar el formato del manifiesto;
- rotar la identidad `age`;
- rotar la clave Transit;
- actualizar PostgreSQL de versión principal;
- modificar el pipeline de backup;
- recuperar OpenBao desde un snapshot.
