-- =============================================================================
-- Ingest 01 · Objects needed to load pNEUMA files
-- Run as: PNEUMA_LOADER
--   snow sql -f snowflake/ingest/01_raw_objects.sql -D db_name=PNEUMA_DEV
--
-- Creates three things in RAW:
--   PNEUMA_STAGE        a storage area inside Snowflake that we upload files to
--   PNEUMA_LINE_FORMAT  tells COPY INTO how to read a pNEUMA file
--   PNEUMA_LINES        the table: one row per line of a file, kept as-is
--
-- Why one row per line, unsplit? Every line in a pNEUMA file is one vehicle,
-- with a different number of values on each line, so it doesn't fit normal
-- columns. We keep the line exactly as it came and split it later in dbt.
--
-- Safe to re-run.
-- =============================================================================

USE SECONDARY ROLES NONE;
USE ROLE PNEUMA_LOADER;
USE DATABASE <% db_name %>;
USE SCHEMA RAW;

-- Internal stage: Snowflake stores the uploaded files for us, no S3 needed.
CREATE STAGE IF NOT EXISTS PNEUMA_STAGE
    COMMENT = 'Uploaded pNEUMA CSV files, waiting to be loaded.';

-- Read the whole line as a single value: no column splitting at all
-- (FIELD_DELIMITER = NONE). Skip the header line.
CREATE FILE FORMAT IF NOT EXISTS PNEUMA_LINE_FORMAT
    TYPE            = CSV
    FIELD_DELIMITER = NONE
    SKIP_HEADER     = 1
    COMMENT         = 'Reads each pNEUMA line as one text value.';

CREATE TABLE IF NOT EXISTS PNEUMA_LINES (
    source_file         VARCHAR       COMMENT 'File the line came from, as named in the stage.',
    line_number         NUMBER        COMMENT 'Line number inside that file.',
    line                VARCHAR       COMMENT 'The full line, untouched: 4 vehicle values, then 6 values per trajectory point.',
    file_last_modified  TIMESTAMP_LTZ COMMENT 'When the file was last changed in the stage.',
    loaded_at           TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP() COMMENT 'When this row was loaded.'
)
COMMENT = 'pNEUMA files, one row per vehicle line, unsplit. Split into tracks and points by dbt.';
