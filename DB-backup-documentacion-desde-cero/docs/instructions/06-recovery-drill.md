# Simulacro de recuperación

## Regla de seguridad

Nunca restaures primero sobre producción.

```mermaid
flowchart LR
  A[Partes cifradas] --> B[Verificar hashes]
  B --> C[Verificar firma Ed25519]
  C --> D[Unir partes]
  D --> E[Descifrar con age offline]
  E --> F[pg_restore --list]
  F --> G[Supabase aislado]
  G --> H[Pruebas de datos]
```

## Qué no restaura un `pg_dump` por sí solo

- Edge Functions desplegadas.
- Secrets de Edge Functions.
- API keys.
- Configuración externa de Auth/OAuth.
- Objetos de Storage.
- Configuración de Fly/OpenBao/GitHub.

Por eso este repositorio guarda además documentación y contratos de instalación.
