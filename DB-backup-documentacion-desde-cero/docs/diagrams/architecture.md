# Arquitectura del backup

## La historia corta

Imagina que la base de datos es un cofre con información importante:

- **Supabase Edge Function** es el timbre que dice: “empieza el backup”.
- **GitHub Actions** es el camión que recoge una copia.
- **age** mete la copia en una caja cerrada.
- **backup-signer** lleva el papel del contenido al notario.
- **OpenBao Transit** pone una firma que no se puede falsificar.
- **GitHub**, en la rama `backups-signed-latest-30`, guarda las últimas 30 cajas.
- **Backup Guardian** revisa que todo siga funcionando cuando cambiamos archivos.

```mermaid
flowchart LR
    A[Supabase PostgreSQL] -->|pg_dump| B[GitHub Actions]
    E[Supabase Edge Function] -->|repository_dispatch| B
    B -->|cifra con age| C[Backup cifrado en partes]
    B -->|OIDC + manifiesto| D[backup-signer en Fly]
    D -->|AppRole de 120 s| F[OpenBao principal]
    F -->|firma Ed25519| D
    D -->|firma| B
    B -->|verifica firma y hashes| G[backups-signed-latest-30]
    H[Backup Guardian] -->|prueba estática y canario real| B
```

## Dónde vive cada cosa

```mermaid
flowchart TB
    subgraph S[Supabase]
      SF[Edge Function trigger-github-backup]
      SS[Secrets de la Edge Function]
      DB[(PostgreSQL)]
    end

    subgraph G[GitHub: DB-backup]
      C[Caller workflow]
      R[Reusable workflow]
      T[tools/backup]
      K[Clave pública y recipient age]
      BG[Backup Guardian]
      BR[Rama backups-signed-latest-30]
    end

    subgraph F[Fly.io]
      BS[camino-backup-signer]
      OB[camino-openbao]
    end

    subgraph O[Fuera de línea]
      AGE[Identidad privada age]
    end

    SF --> C
    C --> R
    R --> DB
    R --> BS
    BS --> OB
    R --> BR
    AGE -. nunca se sube .-> O
```

## Regla de oro

La identidad privada de `age`, el token raíz de OpenBao, `SUPABASE_DB_URL`, el PAT de GitHub y los secretos AppRole **nunca** se guardan en Git ni en esta documentación.
