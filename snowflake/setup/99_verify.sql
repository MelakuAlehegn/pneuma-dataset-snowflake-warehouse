-- =============================================================================
-- 99 · Check the setup worked: things that SHOULD exist and SHOULD work
-- Run with: snow sql -f snowflake/setup/99_verify.sql
--
-- The opposite check (things that should be BLOCKED) is in
-- 99_verify_blocked.sh, because a SQL file stops at its first error.
--
-- Note on "secondary roles": Snowflake may switch on ALL of your roles in the
-- background, so a test could pass using SYSADMIN's rights instead of the role
-- we're testing. The line below turns that off, so each test uses only the
-- role named in USE ROLE.
-- =============================================================================

USE SECONDARY ROLES NONE;

-- ---------------------------------------------------------------------------
-- What exists
-- ---------------------------------------------------------------------------
USE ROLE SYSADMIN;

SHOW WAREHOUSES LIKE '%_WH';                  -- expect LOAD_WH, TRANSFORM_WH, ANALYST_WH
SHOW DATABASES  LIKE 'PNEUMA%';               -- expect PNEUMA_DEV, PNEUMA_PROD
SHOW SCHEMAS         IN DATABASE PNEUMA_PROD; -- expect the 7 schemas (+ INFORMATION_SCHEMA), no PUBLIC
SHOW DATABASE ROLES  IN DATABASE PNEUMA_PROD; -- expect RAW_R, RAW_RW, TRANSFORM_RW, MARTS_R
SHOW GRANTS TO ROLE PNEUMA_ANALYST;           -- expect ANALYST_WH, PNEUMA_PROD.MARTS_R, SNOWFLAKE.CORTEX_USER

-- Things that SHOULD work
USE ROLE PNEUMA_LOADER;
USE WAREHOUSE LOAD_WH;
CREATE TABLE PNEUMA_DEV.RAW.SMOKE_TEST (id INT);
INSERT INTO  PNEUMA_DEV.RAW.SMOKE_TEST VALUES (1);
DROP TABLE   PNEUMA_DEV.RAW.SMOKE_TEST;

USE ROLE PNEUMA_TRANSFORMER;
USE WAREHOUSE TRANSFORM_WH;
CREATE VIEW PNEUMA_DEV.MARTS.SMOKE_TEST AS SELECT 1 AS id;
DROP VIEW   PNEUMA_DEV.MARTS.SMOKE_TEST;
