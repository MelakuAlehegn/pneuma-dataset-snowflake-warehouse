-- =============================================================================
-- Let people open the app
-- Run as: SYSADMIN, after every deploy of the app (safe to re-run)
--   snow sql -f snowflake/app/grant_app_usage.sql
--
-- The APP schema is managed access, so the app's owner (PNEUMA_APP) can't
-- share it itself; SYSADMIN, as schema owner, does. The grant goes to the
-- APP_USE bundle, which PNEUMA_ANALYST already has (04_access.sql).
--
-- Why after every deploy: deploying with --replace recreates the app, and a
-- recreated object can lose the permissions granted on the old one.
-- =============================================================================

USE ROLE SYSADMIN;

GRANT USAGE ON STREAMLIT PNEUMA_PROD.APP.PNEUMA_TRAFFIC_APP TO DATABASE ROLE PNEUMA_PROD.APP_USE;
