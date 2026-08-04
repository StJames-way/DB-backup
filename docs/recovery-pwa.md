# Backup Recovery PWA

## Acceso directo

- **Aplicación:** [https://stjames-way.github.io/backup-recovery-pwa/](https://stjames-way.github.io/backup-recovery-pwa/)
- **Código fuente:** [https://github.com/StJames-way/backup-recovery-pwa](https://github.com/StJames-way/backup-recovery-pwa)
- **Guía visual PDF:** [https://stjames-way.github.io/backup-recovery-pwa/guia-recuperacion-backup-paso-a-paso.pdf](https://stjames-way.github.io/backup-recovery-pwa/guia-recuperacion-backup-paso-a-paso.pdf)
- **Contrato público desplegado:** [https://stjames-way.github.io/backup-recovery-pwa/backup-recovery-trust.json](https://stjames-way.github.io/backup-recovery-pwa/backup-recovery-trust.json)

La PWA es la interfaz guiada de recuperación del sistema `DB-backup`. Vive en
un repositorio separado porque la creación del backup y su recuperación son
planos de seguridad distintos:

```text
DB-backup                      crea, cifra, firma y conserva los backups
backup-recovery-pwa            verifica y une localmente un backup elegido
identidad privada age offline  descifra después de la verificación
PostgreSQL aislado             recibe la restauración de prueba o emergencia
```

## Qué problema resuelve

La rama `backups-signed-latest-30` contiene varias piezas para cada fecha:

```text
manifests/database_backup_<FECHA>.json
signatures/database_backup_<FECHA>.sig
signatures/database_backup_<FECHA>.json       opcional
encrypted_backups/database_backup_<FECHA>.dump.age.aaa.part
encrypted_backups/database_backup_<FECHA>.dump.age.aab.part
```

La PWA evita unir a mano partes de fechas distintas y ofrece una revisión
visible antes de producir el `.dump.age` cifrado.

## Archivos que acepta

| Archivo | Obligatorio | Función |
|---|---:|---|
| `manifests/*.json` | Sí | Inventario firmado del backup |
| `signatures/*.sig` | Sí | Firma Ed25519 del manifiesto canónico |
| `signatures/*.json` | No | Metadatos públicos de la firma |
| `encrypted_backups/*.part` | Sí | Partes consecutivas del `.dump.age` |
| Clave pública PEM | Incluida | Verifica la firma `.sig` |
| `recovery-trust.json` | Incluido | Fija recipient y huellas aprobadas |
| Identidad privada `age` | Nunca | No debe cargarse en el navegador |

Los dos JSON pueden compartir basename porque viven en rutas diferentes:

```text
manifests/database_backup_<FECHA>.json
signatures/database_backup_<FECHA>.json
```

## Qué verifica

La aplicación procesa los archivos localmente y comprueba:

1. schema y contrato del manifiesto;
2. recipient `age` aprobado;
3. huella SHA-256 de la clave pública Ed25519;
4. firma OpenBao Transit del manifiesto;
5. metadatos de firma, cuando se proporcionan;
6. presencia, nombre, tamaño y orden de cada parte;
7. SHA-256 de cada parte;
8. SHA-256 del archivo cifrado unido;
9. coherencia de una única fecha/base de backup.

La lectura de partes es secuencial. Cuando el navegador permite escritura por
streaming, la aplicación puede producir directamente el `.dump.age`; para
backups grandes, más de 100 partes, navegadores incompatibles o por decisión
del operador, genera un kit de terminal.

## Qué no hace

La PWA:

- no sube los archivos a GitHub Pages;
- no utiliza una API de recuperación;
- no pide RoleID, SecretID ni token de OpenBao;
- no pide `SUPABASE_DB_URL`;
- no recibe la identidad privada `age`;
- no descifra el `.dump.age`;
- no ejecuta `pg_restore`;
- no demuestra por sí sola que la base pueda restaurarse.

La firma acredita el manifiesto y los hashes acreditan las partes. La
recuperabilidad completa solo queda probada tras descifrar y restaurar en una
base PostgreSQL aislada.

## Uso recomendado

### 1. Obtén una copia inmutable de la rama de backups

```bash
set -euo pipefail
umask 077

git clone --filter=blob:none \
  --branch backups-signed-latest-30 \
  git@github.com:StJames-way/DB-backup.git \
  DB-backup-restore

cd DB-backup-restore
git rev-parse HEAD | tee RESTORE_SOURCE_COMMIT.txt
```

No trabajes sobre una carpeta sincronizada con iCloud, Dropbox u otro tercero.

### 2. Abre la PWA

Abre:

```text
https://stjames-way.github.io/backup-recovery-pwa/
```

Puedes elegir:

- **Cargar carpeta completa:** selecciona la raíz que contiene
  `manifests/`, `signatures/` y `encrypted_backups/`;
- **Carga manual:** selecciona manifiesto, `.sig`, metadatos opcionales y las
  partes de la misma fecha.

### 3. Revisa la selección

Antes de unir, confirma que la PWA muestra una sola base, por ejemplo:

```text
database_backup_2026-08-04_06-53-27
```

No continúes si aparecen partes ausentes, fechas mezcladas, huellas distintas,
firma inválida o metadatos incompatibles.

### 4. Verifica y une

Usa una de estas salidas:

- **Verificar y unir el backup cifrado:** crea el `.dump.age` desde el
  navegador cuando el entorno lo admite;
- **Generar kit completo de terminal:** produce scripts de verificación,
  unión, descifrado y comprobación para macOS/Linux y PowerShell.

El archivo resultante sigue cifrado:

```text
database_backup_<FECHA>.dump.age
```

### 5. Descifra fuera de la PWA

La identidad privada debe permanecer en un volumen offline o cifrado:

```bash
AGE_IDENTITY='/VOLUMEN-OFFLINE/backup-age-identity.txt'
ENCRYPTED='/VOLUMEN-CIFRADO/restore/database_backup_<FECHA>.dump.age'
DUMP='/VOLUMEN-CIFRADO/restore/database_backup_<FECHA>.dump'

age --decrypt \
  --identity "$AGE_IDENTITY" \
  --output "$DUMP" \
  "$ENCRYPTED"

pg_restore --list "$DUMP" > restore.contents.txt
```

Después sigue [`disaster-recovery.md`](disaster-recovery.md) para restaurar en
una base nueva y aislada.

## Modelo de confianza

La PWA incluye copias públicas de la clave Ed25519 y del contrato de recovery.
Para una recuperación de alta criticidad:

1. registra el commit exacto de `DB-backup` y de `backup-recovery-pwa`;
2. compara el contrato desplegado con `config/backup-recovery-trust.json`;
3. compara la clave pública con `config/backup-signing-public-key.pem`;
4. conserva el informe de la PWA y el SHA del snapshot;
5. usa también las herramientas CLI versionadas como comprobación
   independiente cuando sea posible.

La URL de GitHub Pages es una comodidad operativa, no el único camino de
recuperación. Mantén un clon o release estático del repositorio PWA y el kit de
terminal para poder recuperar si GitHub Pages no está disponible.

## Seguridad de la estación de recuperación

- usa un equipo actualizado y con disco cifrado;
- evita extensiones de navegador no necesarias;
- no cargues la identidad privada `age` en ningún formulario web;
- no copies el dump plano a carpetas sincronizadas;
- no restaures sobre producción;
- destruye la base temporal y el dump plano al finalizar el simulacro;
- en SSD, confía en cifrado y destrucción de la clave/volumen, no en `shred`.

## Verificación operativa de la PWA

Después de un cambio en claves, contrato, formato de manifiesto o build de la
PWA, ejecuta un smoke test:

1. abre la URL publicada en una sesión nueva;
2. carga un backup completo conocido;
3. verifica firma, partes y SHA final;
4. genera el kit de terminal;
5. confirma que la PWA nunca solicita la identidad privada;
6. registra URL, commit de la PWA, commit de la rama de backups y resultado.

## Portabilidad

Al usar este sistema en otro proyecto no reutilices sin más esta PWA publicada.
Debes desplegar una copia propia y actualizar:

- repositorio de backup esperado;
- recipient `age` y su SHA-256;
- clave pública Ed25519 y su huella;
- schema/contrato del manifiesto;
- `recovery-trust.json`;
- nombre y URL de GitHub Pages;
- documentación y pruebas.

La identidad privada `age` nunca forma parte de esa migración de código.
