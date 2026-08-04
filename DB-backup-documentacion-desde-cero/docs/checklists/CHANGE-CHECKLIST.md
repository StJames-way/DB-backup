# Checklist para cambios

- [ ] cambio aislado en rama/MR
- [ ] no se incluyeron secretos
- [ ] hashes recalculados con el formato correcto
- [ ] SHA completo, no rama/tag móvil
- [ ] Worker y signer alineados antes de mover caller
- [ ] `node --check` y tests del signer
- [ ] Guardian en verde
- [ ] `/readyz` desde escala cero
- [ ] canario GitHub success
- [ ] artefactos completos en rama de backups
- [ ] logs sin JWT/manifiestos/secrets expuestos
- [ ] documentación y current contract actualizados
- [ ] recovery drill si cambia formato, cifrado, firma o restore
