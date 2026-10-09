-- =============================================================================
-- 01 · Roles
-- Run as: USERADMIN (the built-in role meant for creating users and roles)
--
-- Creates the three "job" roles. Each person or tool uses exactly one of them:
--   PNEUMA_LOADER       puts raw files into the RAW schema
--   PNEUMA_TRANSFORMER  runs dbt: reads RAW, builds STAGING / INTERMEDIATE / MARTS
--   PNEUMA_ANALYST      can only read the finished MARTS tables in prod.
--                       The Streamlit app and Cortex Analyst run as this role,
--                       so it is the safety boundary for AI-generated SQL.
--
-- These roles hold no table permissions themselves. They get them later
-- (in 04_access.sql) by inheriting small permission bundles defined inside
-- each database.
--
-- Safe to re-run.
-- =============================================================================

USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS PNEUMA_LOADER
    COMMENT = 'Loads raw pNEUMA files into the RAW schema.';

CREATE ROLE IF NOT EXISTS PNEUMA_TRANSFORMER
    COMMENT = 'Runs dbt. Reads RAW, builds STAGING, INTERMEDIATE and MARTS.';

CREATE ROLE IF NOT EXISTS PNEUMA_ANALYST
    COMMENT = 'Read-only on prod MARTS. Used by the Streamlit app and Cortex Analyst.';

-- Place the roles under SYSADMIN. Anything these roles create is then also
-- visible to and manageable by SYSADMIN, so nothing ends up "orphaned".
GRANT ROLE PNEUMA_LOADER      TO ROLE SYSADMIN;
GRANT ROLE PNEUMA_TRANSFORMER TO ROLE SYSADMIN;
GRANT ROLE PNEUMA_ANALYST     TO ROLE SYSADMIN;

-- Give yourself all three so you can switch into each one for testing.
-- (The quotes keep it working even if your user name has dots or @ in it.)
SET my_user = '"' || CURRENT_USER() || '"';
GRANT ROLE PNEUMA_LOADER      TO USER IDENTIFIER($my_user);
GRANT ROLE PNEUMA_TRANSFORMER TO USER IDENTIFIER($my_user);
GRANT ROLE PNEUMA_ANALYST     TO USER IDENTIFIER($my_user);
