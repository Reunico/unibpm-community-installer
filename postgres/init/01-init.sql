CREATE ROLE unibpm  LOGIN PASSWORD 'unibpm';
CREATE ROLE camunda LOGIN PASSWORD 'camunda';
CREATE ROLE keycloak LOGIN PASSWORD 'keycloak';

CREATE DATABASE unibpm  OWNER unibpm;
CREATE DATABASE camunda OWNER camunda;
CREATE DATABASE keycloak OWNER keycloak;
