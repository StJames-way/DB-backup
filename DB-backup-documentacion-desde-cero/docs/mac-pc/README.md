# Scripts para Mac, Linux y WSL2

Los scripts usan Bash, `gh`, `fly`, `jq`, `openssl`, `psql`, `node` y
`wrangler`. En Windows se ejecutan dentro de WSL2.

Ningún script contiene secretos. Los que necesitan tokens los leen de variables
de entorno o archivos temporales con modo 600.
