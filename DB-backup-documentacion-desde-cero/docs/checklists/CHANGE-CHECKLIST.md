# Checklist cada vez que cambias algo

1. Busca el archivo en `docs/instructions/04-update-cascade.md`.
2. Actualiza todos los sitios de la misma fila.
3. No fusiones un PR rojo aunque GitHub te deje.
4. Si cambias reusable/tools/config, crea un SHA aprobado nuevo.
5. Autoriza primero ese SHA en signer y despliega.
6. Después actualiza el caller.
7. Ejecuta Guardian y canario.
8. Si cambias Edge Function, ejecuta además E2E desde Supabase.
9. Si cambias claves, ejecuta restauración aislada.
