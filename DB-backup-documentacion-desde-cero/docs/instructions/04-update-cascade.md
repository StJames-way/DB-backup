# Cascada segura de cambios

## Cambio del reusable o herramientas confiables

Nunca cambies caller, Worker y signer desordenadamente.

### Commit A

Incluye el nuevo reusable, herramientas, claves públicas y hashes. Obtén su SHA.

### Actualiza consumidores de OIDC

Configura Worker y signer para aceptar exactamente Commit A. Despliega ambos.
Mientras el caller siga apuntando al SHA anterior no habrá tráfico con el nuevo
SHA.

### Commit B

Actualiza `supabase-backup-dispatch.yml` para llamar a Commit A. Fusiona y
lanza canario.

El `job_workflow_sha` esperado es Commit A, no Commit B.

## Cambio de gateway URL

1. despliega el Worker nuevo;
2. prueba health/readiness;
3. calcula SHA de URL normalizada sin slash final;
4. actualiza reusable y Guardian;
5. crea Commit A;
6. actualiza Worker/signer al SHA A;
7. fija caller a SHA A mediante Commit B;
8. cambia variable GitHub;
9. canario;
10. retira gateway antiguo.

## Cambio de recipient `age`

Mantén la identidad antigua y la nueva. Los backups históricos no se recifran
automáticamente.

## Cambio de CA

No reemplaces el archivo hasta haber validado la nueva cadena contra el host
real. Cambia archivo y huella en el mismo commit.

## Cambio de clave Transit

Exporta la nueva pública y mantén la pública antigua para verificar backups
históricos. El formato de metadatos incluye `key_version`, pero la política de
recuperación debe conservar las claves públicas necesarias.

## Cambio de rate limits

Prueba:

- una ejecución normal;
- retries de GitHub;
- readiness desde escala cero;
- rechazo 429 deliberado;
- ausencia de bloqueo entre canarios legítimos.
