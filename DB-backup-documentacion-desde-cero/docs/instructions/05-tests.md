# Cómo demostrar que funciona

## Prueba 1: Guardian estático

Debe poner verde:

```text
Guardian / static contract
```

Comprueba sintaxis, archivos generados, claves privadas, SHA inmutables, contrato, huellas y tests deterministas.

## Prueba 2: canario real

Debe poner verde:

```text
Guardian / production canary
```

Hace un backup real, no un dry-run.

## Prueba 3: extremo a extremo desde Supabase

```bash
export SUPABASE_PROJECT_REF="urfbxknxmzcvgogkixdq"
export SUPABASE_FUNCTION_NAME="trigger-github-backup"

"$HOME/.local/bin/test-supabase-backup-e2e"
```

Resultado esperado:

```text
PRUEBA E2E DESDE index.ts: CORRECTA
```


## Protección de `main` con el plan actual

En una organización con repositorio privado y GitHub Free, el ruleset puede quedar configurado pero no aplicado. No hagas público `DB-backup` para resolverlo. Hasta contratar GitHub Team, la regla humana es sencilla: **no fusiones ningún PR con Guardian rojo**, aunque el botón de merge siga disponible.

La rama `backups-signed-latest-30` no debe incluirse en el ruleset de `main`, porque el workflow la actualiza directamente.

## Prueba 4: restauración

1. descargar manifiesto, firma y partes;
2. verificar tamaños y SHA-256;
3. verificar Ed25519;
4. unir partes;
5. descifrar con identidad `age` offline;
6. comparar SHA del dump plano;
7. ejecutar `pg_restore --list`;
8. restaurar en un proyecto Supabase aislado y desechable.

Sin este último paso, el backup está íntegro, pero todavía no está demostrado que sea recuperable.
