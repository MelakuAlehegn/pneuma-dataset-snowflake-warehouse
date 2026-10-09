-- =============================================================================
-- Ingest 99 · Check the load
--   snow sql -f snowflake/ingest/99_check.sql -D db_name=PNEUMA_DEV
-- =============================================================================

USE SECONDARY ROLES NONE;
USE ROLE PNEUMA_LOADER;
USE WAREHOUSE LOAD_WH;
USE DATABASE <% db_name %>;
USE SCHEMA RAW;

-- Files in the stage
LIST @PNEUMA_STAGE;

-- One row per file. For 20181101_d1_0800_0830 expect:
--   lines = 785, longest_line ~ 1,179,750 characters
SELECT
    source_file,
    COUNT(*)            AS lines,
    MIN(line_number)    AS first_line,
    MAX(line_number)    AS last_line,
    MAX(LENGTH(line))   AS longest_line,
    MIN(loaded_at)      AS loaded_at
FROM PNEUMA_LINES
GROUP BY source_file;

-- Peek at the start of the first line (should begin with "1; Motorcycle; ...")
SELECT line_number, LEFT(line, 120) AS line_start
FROM PNEUMA_LINES
ORDER BY line_number
LIMIT 3;

-- Load history for this table: shows each file, status and rows loaded
SELECT file_name, status, row_count, first_error_message, last_load_time
FROM INFORMATION_SCHEMA.LOAD_HISTORY
WHERE table_name = 'PNEUMA_LINES'
ORDER BY last_load_time DESC;
