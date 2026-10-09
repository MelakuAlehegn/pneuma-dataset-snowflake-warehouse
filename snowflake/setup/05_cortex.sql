-- =============================================================================
-- 05 · Cortex access
-- Run as: ACCOUNTADMIN (only this role can hand out Snowflake's own built-in
--         permission bundles)
--
-- By default every user can call Cortex AI features, because Snowflake gives
-- CORTEX_USER to the PUBLIC role. We grant it to PNEUMA_ANALYST and
-- PNEUMA_APP directly as well, so things keep working even if an admin later
-- removes it from PUBLIC (a common lock-down step in real accounts).
--
-- Safe to re-run.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE PNEUMA_ANALYST;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE PNEUMA_APP;
