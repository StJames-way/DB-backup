-- Plantilla para crear el rol de backup de solo lectura.
-- Ejecutar en Supabase SQL Editor como un rol administrador.
-- Sustituir la contraseña fuera de Git y no reutilizarla.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'backup_reader') THEN
    CREATE ROLE backup_reader
    WITH
      LOGIN
      PASSWORD 'REEMPLAZAR_CON_PASSWORD_ALEATORIA_MUY_LARGA'
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      INHERIT
      NOREPLICATION
      BYPASSRLS
      CONNECTION LIMIT 10;
  END IF;
END
$$;

ALTER ROLE backup_reader CONNECTION LIMIT 10;
ALTER ROLE backup_reader SET idle_session_timeout = '5min';
ALTER ROLE backup_reader SET idle_in_transaction_session_timeout = '2min';
ALTER ROLE backup_reader SET lock_timeout = '30s';
ALTER ROLE backup_reader SET statement_timeout = '2h';

-- Permisos mínimos para un backup lógico de los datos de aplicación,
-- Auth, metadatos de Storage y migraciones. Ajustar si la base no se llama postgres.
GRANT CONNECT ON DATABASE postgres TO backup_reader;
GRANT USAGE ON SCHEMA public, auth, storage, supabase_migrations TO backup_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public, auth, storage, supabase_migrations TO backup_reader;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public, auth, storage, supabase_migrations TO backup_reader;

-- Los ALTER DEFAULT PRIVILEGES afectan solo a objetos futuros creados por el
-- rol que ejecuta cada sentencia. Repetirlos como cada propietario real.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO backup_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON SEQUENCES TO backup_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
  GRANT SELECT ON TABLES TO backup_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage
  GRANT SELECT ON TABLES TO backup_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA supabase_migrations
  GRANT SELECT ON TABLES TO backup_reader;

-- Para incluir otros schemas con datos relevantes, por ejemplo vault, cron o
-- net, concédeles también USAGE y SELECT tras valorar su sensibilidad.

-- Defensa adicional: retirar creación en public si no es necesaria.
REVOKE CREATE ON SCHEMA public FROM backup_reader;

-- Auditoría del resultado.
SELECT
  rolname,
  rolcanlogin,
  rolconnlimit,
  rolbypassrls,
  rolconfig
FROM pg_roles
WHERE rolname = 'backup_reader';

-- Ver conexiones actuales.
SELECT
  pid,
  usename,
  application_name,
  client_addr,
  state,
  backend_start,
  state_change
FROM pg_stat_activity
WHERE usename = 'backup_reader'
ORDER BY backend_start;

-- Operación de emergencia: cerrar sesiones residuales antes de un canario.
-- No la programes como tarea periódica.
-- SELECT pg_terminate_backend(pid)
-- FROM pg_stat_activity
-- WHERE usename = 'backup_reader'
--   AND pid <> pg_backend_pid();
