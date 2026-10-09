-- =============================================================================
-- 01 · Roles
-- Run as: USERADMIN (the built-in role meant for creating users and roles)
--
-- Creates the four "job" roles. Each person or tool uses exactly one of them:
--   PNEUMA_LOADER       puts raw files into the RAW schema
--   PNEUMA_TRANSFORMER  runs dbt: reads RAW, builds STAGING / INTERMEDIATE / MARTS
--   PNEUMA_ANALYST      a person: can only read the finished MARTS tables in
--                       prod, ask Cortex Analyst, and open the app
--   PNEUMA_APP          owns and runs the Streamlit app. Same read-only access
--                       as the analyst, plus creating apps in the APP schema.
--                       A Streamlit app runs with its OWNER's permissions, so
--                       this role is the safety boundary for AI-written SQL.
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
    COMMENT = 'Read-only on prod MARTS; can ask Cortex Analyst and open the app.';

CREATE ROLE IF NOT EXISTS PNEUMA_APP
    COMMENT = 'Owns and runs the Streamlit app. Read-only on prod MARTS.';

-- Place the roles under SYSADMIN. Anything these roles create is then also
-- visible to and manageable by SYSADMIN, so nothing ends up "orphaned".
GRANT ROLE PNEUMA_LOADER      TO ROLE SYSADMIN;
GRANT ROLE PNEUMA_TRANSFORMER TO ROLE SYSADMIN;
GRANT ROLE PNEUMA_ANALYST     TO ROLE SYSADMIN;
GRANT ROLE PNEUMA_APP         TO ROLE SYSADMIN;

-- Give yourself all three so you can switch into each one for testing.
-- (The quotes keep it working even if your user name has dots or @ in it.)
SET my_user = '"' || CURRENT_USER() || '"';
GRANT ROLE PNEUMA_LOADER      TO USER IDENTIFIER($my_user);
GRANT ROLE PNEUMA_TRANSFORMER TO USER IDENTIFIER($my_user);
GRANT ROLE PNEUMA_ANALYST     TO USER IDENTIFIER($my_user);
GRANT ROLE PNEUMA_APP         TO USER IDENTIFIER($my_user);
