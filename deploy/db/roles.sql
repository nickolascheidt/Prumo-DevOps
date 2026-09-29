-- COPY of db/roles.sql in the Prumo repo. The two must move together: change it
-- there and copy it here again, never the other way around.
-- Separates who runs DDL from who runs the application.
--
--   prumo_migrator  owns the tables in `public`; the only role that can create or alter
--                   schema. Used by `dotnet ef` and by the deploy's migration step.
--   prumo_app       DML only. This is the credential the API connects with.
--
-- Idempotent: run it as many times as you like, on a new or an existing database.
--
-- To apply it to a database that already exists:
--   docker exec -i saasbase-postgres psql -U postgres -d SaaSBasePlatformDb < db/roles.sql
--
-- On a new volume docker-compose runs this file by itself, through
-- docker-entrypoint-initdb.d, against the `POSTGRES_DB` database.
--
-- Passwords come from the PRUMO_MIGRATOR_PASSWORD and PRUMO_APP_PASSWORD environment
-- variables. Without them they fall back to the development values below, which match
-- `appsettings.json` and must not exist outside your machine.

\getenv migrator_password PRUMO_MIGRATOR_PASSWORD
\getenv app_password PRUMO_APP_PASSWORD

\if :{?migrator_password} \else \set migrator_password 'prumo_migrator_dev' \endif
\if :{?app_password}      \else \set app_password 'prumo_app_dev'          \endif

BEGIN;

-- 1. The two roles. CREATE ROLE has no IF NOT EXISTS, hence the DO block.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'prumo_migrator') THEN
        CREATE ROLE prumo_migrator LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'prumo_app') THEN
        CREATE ROLE prumo_app LOGIN;
    END IF;
END
$$;

ALTER ROLE prumo_migrator WITH PASSWORD :'migrator_password';
ALTER ROLE prumo_app      WITH PASSWORD :'app_password';

-- 2. The migrator becomes the owner of everything already in `public`.
--    Without this the separation is an illusion: whoever owns a table can run DDL on
--    it regardless of grants.
DO $$
DECLARE
    obj record;
BEGIN
    FOR obj IN
        SELECT tablename AS name FROM pg_tables
        WHERE schemaname = 'public' AND tableowner <> 'prumo_migrator'
    LOOP
        EXECUTE format('ALTER TABLE public.%I OWNER TO prumo_migrator', obj.name);
    END LOOP;

    FOR obj IN
        SELECT sequencename AS name FROM pg_sequences
        WHERE schemaname = 'public' AND sequenceowner <> 'prumo_migrator'
    LOOP
        EXECUTE format('ALTER SEQUENCE public.%I OWNER TO prumo_migrator', obj.name);
    END LOOP;
END
$$;

GRANT CREATE, USAGE ON SCHEMA public TO prumo_migrator;

-- 3. The application: DML and nothing else.
GRANT USAGE ON SCHEMA public TO prumo_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO prumo_app;
GRANT USAGE, SELECT, UPDATE           ON ALL SEQUENCES IN SCHEMA public TO prumo_app;

-- 4. Tables created by future migrations are born accessible to the app. Without this,
--    every migration with a new table would require remembering to edit this file — and
--    forgetting would only show up as a 500 at runtime.
ALTER DEFAULT PRIVILEGES FOR ROLE prumo_migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO prumo_app;
ALTER DEFAULT PRIVILEGES FOR ROLE prumo_migrator IN SCHEMA public
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO prumo_app;

-- 5. Nobody else creates objects in `public`. Postgres 15+ already revokes it from
--    PUBLIC; the line stays because it states the intent, and it is cheap.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM prumo_app;

COMMIT;
