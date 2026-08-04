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
2. abrir la [Backup Recovery PWA](https://stjames-way.github.io/backup-recovery-pwa/) o una copia local fijada;
3. verificar el trust público;
4. verificar la firma del manifiesto;
5. verificar todas las partes y hashes;
6. concatenar las partes en orden lexicográfico o dejar que la PWA las una;
7. descifrar con la identidad offline;
8. comprobar `pg_restore --list`;
9. crear una base aislada;
10. restaurar sin owner/privileges;
11. ejecutar checks de tablas, funciones y conteos;
12. destruir la base de prueba;
13. guardar un acta sin datos sensibles.

## Criterios de éxito

- la PWA carga y verifica el conjunto sin solicitar la identidad privada;
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
URL y commit/build de backup-recovery-pwa
resultado/informe de la PWA
resultado de verify_backup_set
resultado de verify_signature
resultado de verify_plaintext_dump
resumen del restore
incidencias
responsable
```

## Prueba mínima de la interfaz de recuperación

1. abre [https://stjames-way.github.io/backup-recovery-pwa/](https://stjames-way.github.io/backup-recovery-pwa/) en una sesión nueva;
2. carga la carpeta con `manifests/`, `signatures/` y `encrypted_backups/`;
3. verifica que la firma, cada parte y el SHA final quedan en verde;
4. genera el kit de terminal;
5. confirma que el resultado sigue siendo `.dump.age`;
6. comprueba que no se solicita la identidad privada `age`;
7. continúa con descifrado y `pg_restore` aislado.

La PWA mejora la ergonomía, pero el simulacro no termina hasta validar la base
restaurada.
