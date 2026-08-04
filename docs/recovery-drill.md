# Simulacro de recuperación

## Objetivo

Demostrar que un backup firmado y cifrado puede convertirse en una base
PostgreSQL utilizable sin tocar producción.

## Frecuencia

- después de cualquier cambio en formato, cifrado, firma o permisos;
- al menos trimestralmente;
- antes de retirar una identidad `age` antigua;
- antes de una migración de PostgreSQL mayor.

## Selección del backup

Usa un backup reciente, por ejemplo una base con estructura:

```text
database_backup_2026-08-04_06-53-27
```

No fijes ese nombre en scripts permanentes; selecciona el manifiesto más
reciente válido.

## Fases

1. clonar la rama de backups y fijar su commit;
2. verificar trust público;
3. verificar firma del manifiesto;
4. verificar todas las partes y hashes;
5. concatenar partes en orden lexicográfico;
6. descifrar con la identidad offline;
7. comprobar `pg_restore --list`;
8. crear base aislada;
9. restaurar sin owner/privileges;
10. ejecutar checks de tablas, funciones y conteos;
11. destruir la base de prueba;
12. guardar acta sin datos sensibles.

## Criterios de éxito

- firma válida;
- partes completas;
- hash cifrado y hash plano correctos;
- dump legible por `pg_restore`;
- restore termina sin errores críticos;
- consultas de humo devuelven resultados esperados;
- no hubo conexión a producción durante el proceso.

## Evidencia a conservar

```text
fecha
git commit de la rama de backups
nombre base del backup
versiones de age, Python y PostgreSQL
resultado de verify_backup_set
resultado de verify_signature
resultado de verify_plaintext_dump
resumen del restore
incidencias
responsable
```
