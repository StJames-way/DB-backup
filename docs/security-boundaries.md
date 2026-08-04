# Fronteras de seguridad

## Activos

1. contenido de PostgreSQL;
2. identidad privada `age`;
3. credenciales `backup_reader`;
4. clave privada Transit;
5. secretos AppRole;
6. secreto Worker -> signer;
7. token de readiness;
8. token de Tunnel;
9. PAT de la Edge Function para `repository_dispatch`.

## Dónde puede vivir cada secreto

| Secreto | GitHub | Cloudflare | Fly signer | Fly tunnel | Supabase | Offline |
|---|---:|---:|---:|---:|---:|---:|
| `SUPABASE_DB_URL` | sí | no | no | no | no | opcional |
| identidad privada `age` | no | no | no | no | no | sí |
| `BACKUP_GATEWAY_TOKEN` | no | sí | sí | no | no | temporal de provisión |
| `BACKUP_HEALTH_TOKEN` | no | sí | no | no | no | cliente autorizado |
| `OPENBAO_ROLE_ID/SECRET_ID` | no | no | sí | no | no | provisión |
| `TUNNEL_TOKEN` | no | no | no | sí | no | provisión |
| PAT dispatch GitHub | no | no | no | no | Edge Function | provisión |
| trigger secret | no | no | no | no | Edge + Vault | provisión |

## Principios

- No confiar en una única barrera.
- Validar OIDC en Worker y signer.
- No exponer OpenBao a Internet.
- No enviar el dump al servicio de firma.
- No almacenar la identidad privada `age` junto al backup.
- Mantener el reusable fijado a SHA.
- Verificar todas las huellas públicas antes de usar el backup.
- Falla cerrada ante errores JWKS, CA, hashes o firma.

## BYPASSRLS

`backup_reader` tiene `BYPASSRLS` para que un dump completo no omita filas por
políticas RLS. Es un privilegio elevado de lectura. Debe compensarse con:

- ausencia de grants de escritura;
- contraseña única;
- límite de conexiones;
- timeouts de sesión;
- uso exclusivo desde GitHub;
- rotación periódica;
- auditoría de `pg_stat_activity`.

## Amenazas cubiertas

| Amenaza | Controles |
|---|---|
| robo de un backup almacenado | cifrado `age` y clave offline |
| modificación de partes | hashes del manifiesto |
| sustitución de manifiesto | firma Ed25519 y verificación local |
| workflow no aprobado | SHA fijado + claims OIDC |
| petición falsa al Worker | firma JWT, claims y rate limits |
| petición directa al signer | gateway token + OIDC repetido |
| MITM contra Supabase | `verify-full` + CA aprobada |
| MITM contra OpenBao | HTTPS privado + CA propia |
| abuso masivo del endpoint | límites Worker, tamaño y signer privado |
| filtración de clave Transit | clave no exportable |

## Amenazas no resueltas por sí solas

- compromiso de la cuenta GitHub con permisos para cambiar `main`;
- compromiso del runner durante el dump;
- pérdida de la identidad privada `age`;
- error lógico que genere un dump incompleto pero formalmente válido;
- indisponibilidad simultánea de GitHub, Cloudflare, Fly u OpenBao;
- backups no restaurables por incompatibilidades futuras.

Por eso siguen siendo obligatorios branch protection, revisiones, copias de la
identidad `age`, monitorización y simulacros de recuperación.
