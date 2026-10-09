-- =============================================================================
-- 04 · Hand the permission bundles to the job roles
-- Run as: SYSADMIN   (after 03_database.sql has run for BOTH databases)
--
-- This file is the single place that answers "who can do what":
--
--                       PNEUMA_DEV                 PNEUMA_PROD
--   PNEUMA_LOADER       RAW_RW                     RAW_RW
--   PNEUMA_TRANSFORMER  RAW_R + TRANSFORM_RW       RAW_R + TRANSFORM_RW
--   PNEUMA_ANALYST      -                          MARTS_R
--
-- The analyst role only ever sees finished prod tables, read-only.
--
-- Safe to re-run.
-- =============================================================================

USE ROLE SYSADMIN;

-- Loader
GRANT DATABASE ROLE PNEUMA_DEV.RAW_RW        TO ROLE PNEUMA_LOADER;
GRANT DATABASE ROLE PNEUMA_PROD.RAW_RW       TO ROLE PNEUMA_LOADER;

-- Transformer (dbt)
GRANT DATABASE ROLE PNEUMA_DEV.RAW_R         TO ROLE PNEUMA_TRANSFORMER;
GRANT DATABASE ROLE PNEUMA_DEV.TRANSFORM_RW  TO ROLE PNEUMA_TRANSFORMER;
GRANT DATABASE ROLE PNEUMA_PROD.RAW_R        TO ROLE PNEUMA_TRANSFORMER;
GRANT DATABASE ROLE PNEUMA_PROD.TRANSFORM_RW TO ROLE PNEUMA_TRANSFORMER;

-- Analyst (app + Cortex Analyst)
GRANT DATABASE ROLE PNEUMA_PROD.MARTS_R      TO ROLE PNEUMA_ANALYST;
