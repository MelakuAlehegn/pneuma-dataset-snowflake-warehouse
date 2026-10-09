-- =============================================================================
-- 03 · Database, schemas and permission bundles
-- Run as: SYSADMIN
--
-- RUN THIS FILE TWICE, passing the database name from the command line:
--   snow sql -f snowflake/setup/03_database.sql -D db_name=PNEUMA_DEV
--   snow sql -f snowflake/setup/03_database.sql -D db_name=PNEUMA_PROD
-- The CLI swaps <% db_name %> below for the value you pass. Both databases end
-- up identical. (In a Snowsight worksheet, type the name in by hand instead.)
--
-- What it builds inside the database:
--   Schemas   RAW, STAGING, INTERMEDIATE, MARTS   the data layers
--             SEMANTIC                            the Cortex Analyst YAML file (later)
--             APP                                 the Streamlit app (later)
--             OPS                                 scheduled tasks and alerts (later)
--
--   Permission bundles ("database roles") that live inside this database:
--             RAW_R         read RAW
--             RAW_RW        read and load RAW              (includes RAW_R)
--             TRANSFORM_RW  build tables/views in STAGING, INTERMEDIATE, MARTS
--             MARTS_R       read MARTS
--   These get handed to the job roles in 04_access.sql. Because they live
--   inside the database, they come along automatically when the database is
--   cloned.
--
-- All schemas use MANAGED ACCESS: only the schema owner (SYSADMIN) can hand out
-- permissions, even on tables someone else created. That keeps every grant in
-- these scripts instead of scattered across whoever happened to create a table.
--
-- Safe to re-run.
-- =============================================================================

USE ROLE SYSADMIN;

SET db_name = '<% db_name %>';

CREATE DATABASE IF NOT EXISTS IDENTIFIER($db_name);
USE DATABASE IDENTIFIER($db_name);

-- Every new database comes with an empty PUBLIC schema. We don't use it.
DROP SCHEMA IF EXISTS PUBLIC;

-- ---------------------------------------------------------------------------
-- Schemas
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS RAW          WITH MANAGED ACCESS COMMENT = 'Raw pNEUMA data, loaded as-is.';
CREATE SCHEMA IF NOT EXISTS STAGING      WITH MANAGED ACCESS COMMENT = 'dbt: cleaned and renamed copies of RAW.';
CREATE SCHEMA IF NOT EXISTS INTERMEDIATE WITH MANAGED ACCESS COMMENT = 'dbt: reusable in-between logic.';
CREATE SCHEMA IF NOT EXISTS MARTS        WITH MANAGED ACCESS COMMENT = 'dbt: final tables for analysis and the app.';
CREATE SCHEMA IF NOT EXISTS SEMANTIC     WITH MANAGED ACCESS COMMENT = 'Cortex Analyst semantic model files.';
CREATE SCHEMA IF NOT EXISTS APP          WITH MANAGED ACCESS COMMENT = 'Streamlit app.';
CREATE SCHEMA IF NOT EXISTS OPS          WITH MANAGED ACCESS COMMENT = 'Scheduled tasks, alerts and other plumbing.';

-- ---------------------------------------------------------------------------
-- Permission bundles
-- ---------------------------------------------------------------------------
CREATE DATABASE ROLE IF NOT EXISTS RAW_R        COMMENT = 'Read RAW.';
CREATE DATABASE ROLE IF NOT EXISTS RAW_RW       COMMENT = 'Read and load RAW.';
CREATE DATABASE ROLE IF NOT EXISTS TRANSFORM_RW COMMENT = 'Build objects in STAGING, INTERMEDIATE and MARTS.';
CREATE DATABASE ROLE IF NOT EXISTS MARTS_R      COMMENT = 'Read MARTS.';

-- RAW_RW can do everything RAW_R can, plus write.
GRANT DATABASE ROLE RAW_R TO DATABASE ROLE RAW_RW;

-- Every bundle needs to be able to "see" the database itself.
GRANT USAGE ON DATABASE IDENTIFIER($db_name) TO DATABASE ROLE RAW_R;
GRANT USAGE ON DATABASE IDENTIFIER($db_name) TO DATABASE ROLE TRANSFORM_RW;
GRANT USAGE ON DATABASE IDENTIFIER($db_name) TO DATABASE ROLE MARTS_R;

-- RAW_R: read every table in RAW, including tables created later
-- ("FUTURE" grants apply automatically to tables that don't exist yet).
GRANT USAGE  ON SCHEMA RAW                  TO DATABASE ROLE RAW_R;
GRANT SELECT ON ALL TABLES    IN SCHEMA RAW TO DATABASE ROLE RAW_R;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW TO DATABASE ROLE RAW_R;

-- RAW_RW: create the things a loader needs (tables, stages for files,
-- file formats, pipes) and write to any table in RAW.
GRANT CREATE TABLE, CREATE STAGE, CREATE FILE FORMAT, CREATE PIPE
    ON SCHEMA RAW TO DATABASE ROLE RAW_RW;
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES    IN SCHEMA RAW TO DATABASE ROLE RAW_RW;
GRANT INSERT, UPDATE, DELETE, TRUNCATE ON FUTURE TABLES IN SCHEMA RAW TO DATABASE ROLE RAW_RW;

-- TRANSFORM_RW: dbt creates (and therefore owns) the tables and views it
-- builds, so it only needs permission to create them in its three schemas.
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA STAGING      TO DATABASE ROLE TRANSFORM_RW;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA INTERMEDIATE TO DATABASE ROLE TRANSFORM_RW;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA MARTS        TO DATABASE ROLE TRANSFORM_RW;

-- The dbt project itself is stored as an object in OPS.
GRANT USAGE, CREATE DBT PROJECT ON SCHEMA OPS TO DATABASE ROLE TRANSFORM_RW;

-- MARTS_R: read every table and view in MARTS, including future ones, so
-- each dbt rebuild is readable right away without re-granting.
GRANT USAGE  ON SCHEMA MARTS                    TO DATABASE ROLE MARTS_R;
GRANT SELECT ON ALL TABLES    IN SCHEMA MARTS   TO DATABASE ROLE MARTS_R;
GRANT SELECT ON FUTURE TABLES IN SCHEMA MARTS   TO DATABASE ROLE MARTS_R;
GRANT SELECT ON ALL VIEWS     IN SCHEMA MARTS   TO DATABASE ROLE MARTS_R;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA MARTS   TO DATABASE ROLE MARTS_R;
