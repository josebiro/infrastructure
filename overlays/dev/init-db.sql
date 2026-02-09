-- Database initialization script for Polaris development environment
-- This script runs automatically via /docker-entrypoint-initdb.d
-- Creates databases and enables required extensions for all Polaris services

-- Create databases for each service
CREATE DATABASE incident_crawler;
CREATE DATABASE incident_pipeline;
CREATE DATABASE polaris;

-- Create polaris user with access to all databases
CREATE USER polaris WITH PASSWORD 'polaris_dev_password';

-- Grant privileges on incident_crawler database
\c incident_crawler
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;
GRANT ALL PRIVILEGES ON DATABASE incident_crawler TO polaris;
GRANT ALL PRIVILEGES ON SCHEMA public TO polaris;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO polaris;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO polaris;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO polaris;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO polaris;

-- Grant privileges on incident_pipeline database
\c incident_pipeline
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;
GRANT ALL PRIVILEGES ON DATABASE incident_pipeline TO polaris;
GRANT ALL PRIVILEGES ON SCHEMA public TO polaris;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO polaris;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO polaris;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO polaris;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO polaris;

-- Grant privileges on polaris database
\c polaris
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;
GRANT ALL PRIVILEGES ON DATABASE polaris TO polaris;
GRANT ALL PRIVILEGES ON SCHEMA public TO polaris;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO polaris;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO polaris;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO polaris;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO polaris;

-- Switch back to default database
\c postgres
