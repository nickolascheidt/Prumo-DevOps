-- CÓPIA de db/roles.sql do repo Prumo. As duas precisam andar juntas:
-- se lá mudar, aqui muda. Não edite este arquivo; edite o de lá e copie de novo.
-- Separa quem faz DDL de quem roda a aplicação (item 11 do MVP-BACKLOG).
--
--   prumo_migrator  dono das tabelas de `public`, único que pode criar/alterar schema.
--                   Usado pelo `dotnet ef` e pelo passo de migration do deploy.
--   prumo_app       só DML. É com esta credencial que a API conecta.
--
-- Idempotente: pode rodar quantas vezes quiser, em banco novo ou já povoado.
--
-- Como aplicar num banco que já existe:
--   docker exec -i saasbase-postgres psql -U postgres -d SaaSBasePlatformDb < db/roles.sql
--
-- Em banco novo o docker-compose já roda este arquivo sozinho, pelo
-- docker-entrypoint-initdb.d. Nesse caso ele roda contra a base `POSTGRES_DB`.
--
-- As senhas vêm das variáveis de ambiente PRUMO_MIGRATOR_PASSWORD e
-- PRUMO_APP_PASSWORD. Sem elas, caem nos valores de desenvolvimento abaixo, que
-- combinam com o `appsettings.json` e não devem existir fora da sua máquina.

\getenv migrator_password PRUMO_MIGRATOR_PASSWORD
\getenv app_password PRUMO_APP_PASSWORD

\if :{?migrator_password} \else \set migrator_password 'prumo_migrator_dev' \endif
\if :{?app_password}      \else \set app_password 'prumo_app_dev'          \endif

BEGIN;

-- 1. Os dois roles. CREATE ROLE não tem IF NOT EXISTS, daí o DO.
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

-- 2. O migrator passa a ser dono de tudo que já existe em `public`.
--    Sem isto a separação é ilusória: quem possui a tabela faz DDL nela
--    independentemente de grant.
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

-- 3. A aplicação: DML e nada mais.
GRANT USAGE ON SCHEMA public TO prumo_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO prumo_app;
GRANT USAGE, SELECT, UPDATE           ON ALL SEQUENCES IN SCHEMA public TO prumo_app;

-- 4. Tabela que migration futura criar já nasce acessível ao app. Sem isto, toda
--    migration com tabela nova exigiria lembrar de reeditar este arquivo — e o
--    esquecimento só apareceria como 500 em runtime.
ALTER DEFAULT PRIVILEGES FOR ROLE prumo_migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO prumo_app;
ALTER DEFAULT PRIVILEGES FOR ROLE prumo_migrator IN SCHEMA public
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO prumo_app;

-- 5. Ninguém mais cria objeto em `public`. O Postgres 15+ já revoga de PUBLIC;
--    a linha fica porque é ela que expressa a intenção, e é barata.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM prumo_app;

COMMIT;
