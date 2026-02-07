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

SELECT format('CREATE DATABASE %I OWNER %I', 'unibpm', 'unibpm')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'unibpm') \gexec;

SELECT format('CREATE DATABASE %I OWNER %I', 'camunda', 'camunda')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'camunda') \gexec;

SELECT format('CREATE DATABASE %I OWNER %I', 'keycloak', 'keycloak')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'keycloak') \gexec;
