# Mapa de archivos: qué va en cada sitio

## Repositorio `StJames-way/DB-backup`

```text
DB-backup/
├── .github/
│   └── workflows/
│       ├── supabase-backup-dispatch.yml
│       ├── supabase-age-openbao-reusable.yml
│       └── backup-guardian.yml
├── config/
│   ├── age-recipient.txt
│   └── backup-signing-public-key.pem
├── tools/
│   └── backup/
│       ├── build_manifest.py
│       ├── verify_backup_set.py
│       ├── verify_signature.py
│       ├── restore_backup.py
│       ├── verify_plaintext_dump.py
│       └── requirements.txt
├── scripts/
├── restore_age_backup_complete.sh
└── docs/
    ├── README.md
    ├── instructions/
    ├── diagrams/
    ├── supabase/
    ├── mac-pc/
    ├── openbao/
    ├── backup-signer/
    └── checklists/
```

### Qué hace cada archivo importante

| Archivo | Trabajo |
|---|---|
| `.github/workflows/supabase-backup-dispatch.yml` | Es el botón de entrada de GitHub. Recibe `repository_dispatch` o ejecución manual y llama al reusable fijado a un SHA |
| `.github/workflows/supabase-age-openbao-reusable.yml` | Hace el dump, cifra, parte, firma, verifica, conserva 30 y publica |
| `.github/workflows/backup-guardian.yml` | Vigila cambios y ejecuta un backup canario real tras cambios importantes |
| `config/age-recipient.txt` | Contiene solo la clave pública `age1...` |
| `config/backup-signing-public-key.pem` | Clave pública Ed25519 de OpenBao para comprobar firmas |
| `tools/backup/*.py` | Construyen y verifican manifiestos, partes y firmas |
| `docs/supabase/index.ts` | Copia documentada del código de la Edge Function |
| `docs/supabase/config.toml.snippet` | Configura `verify_jwt = false` de forma reproducible |
| `docs/supabase/schedule.sql.example` | Plantilla del reloj `pg_cron` + `pg_net` usando Vault |
| `docs/mac-pc/backup-guardian-v4.yml` | Plantilla del Guardian que se instala en `.github/workflows/backup-guardian.yml` |

## Repositorio `StJames-way/backup-signer`

```text
backup-signer/
├── .github/workflows/ci.yml
├── app/
├── tests/
├── certs/camino-openbao-ca.pem
├── openbao/backup-signer-policy.hcl
├── Dockerfile
├── fly.toml
├── pyproject.toml
└── README.md
```

No necesita variables ni secretos en GitHub. Su CI construye y prueba, pero no despliega.

## Supabase

```text
Edge Function desplegada:
trigger-github-backup

Código documentado:
docs/supabase/index.ts

Ruta local de despliegue:
supabase/functions/trigger-github-backup/index.ts
```

## Mac o PC

Los scripts Bash se instalan en:

```text
$HOME/.local/bin/
```

En Windows se ejecutan dentro de **WSL2 con Ubuntu**. No se ejecutan directamente desde `cmd.exe`.
