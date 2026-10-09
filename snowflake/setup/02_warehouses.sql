-- =============================================================================
-- 02 · Warehouses
-- Run as: SYSADMIN
--
-- One warehouse per kind of work, so loading, dbt runs and app queries never
-- compete for the same compute, and query history shows clearly who used what.
-- All are the smallest size, start paused, and pause again after 60 seconds idle.
--
-- Safe to re-run.
-- =============================================================================

USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS LOAD_WH
    WAREHOUSE_SIZE      = XSMALL
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Loading raw files.';

CREATE WAREHOUSE IF NOT EXISTS TRANSFORM_WH
    WAREHOUSE_SIZE      = XSMALL
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'dbt runs.';

CREATE WAREHOUSE IF NOT EXISTS ANALYST_WH
    WAREHOUSE_SIZE      = XSMALL
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Streamlit app and Cortex Analyst queries.';

-- Time limits per query. A runaway query would otherwise run for up to 2 days
-- (Snowflake's default). Set with ALTER, not inside CREATE, so re-running this
-- file also updates warehouses that already exist.
--   LOAD_WH       30 min  (a big batch of files can take a while)
--   TRANSFORM_WH  15 min  (a full dbt build takes ~1 min today)
--   ANALYST_WH     1 min  (app queries should be fast; stops bad AI-written SQL)
ALTER WAREHOUSE LOAD_WH      SET STATEMENT_TIMEOUT_IN_SECONDS = 1800;
ALTER WAREHOUSE TRANSFORM_WH SET STATEMENT_TIMEOUT_IN_SECONDS = 900;
ALTER WAREHOUSE ANALYST_WH   SET STATEMENT_TIMEOUT_IN_SECONDS = 60;

-- Each role can use only its own warehouse.
GRANT USAGE ON WAREHOUSE LOAD_WH      TO ROLE PNEUMA_LOADER;
GRANT USAGE ON WAREHOUSE TRANSFORM_WH TO ROLE PNEUMA_TRANSFORMER;
GRANT USAGE ON WAREHOUSE ANALYST_WH   TO ROLE PNEUMA_ANALYST;
