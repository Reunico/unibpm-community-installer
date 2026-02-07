DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'unibpm') THEN
    CREATE ROLE unibpm LOGIN PASSWORD 'unibpm';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'camunda') THEN
    CREATE ROLE camunda LOGIN PASSWORD 'camunda';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'keycloak') THEN
    CREATE ROLE keycloak LOGIN PASSWORD 'keycloak';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'unibpm') THEN
    CREATE DATABASE unibpm OWNER unibpm;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'camunda') THEN
    CREATE DATABASE camunda OWNER camunda;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'keycloak') THEN
    CREATE DATABASE keycloak OWNER keycloak;
  END IF;
END $$;

GRANT ALL PRIVILEGES ON DATABASE unibpm TO unibpm;
GRANT ALL PRIVILEGES ON DATABASE camunda TO camunda;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
