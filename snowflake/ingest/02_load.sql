-- =============================================================================
-- Ingest 02 · Load uploaded files into RAW.PNEUMA_LINES
-- Run as: PNEUMA_LOADER, after uploading files to the stage
--   snow sql -f snowflake/ingest/02_load.sql -D db_name=PNEUMA_DEV
--
-- Loads every CSV file in the stage. Safe to re-run: Snowflake remembers
-- which files it already loaded into this table (for 64 days) and skips them,
-- so the same file is never loaded twice by accident.
-- =============================================================================

USE SECONDARY ROLES NONE;
USE ROLE PNEUMA_LOADER;
USE WAREHOUSE LOAD_WH;
USE DATABASE <% db_name %>;
USE SCHEMA RAW;

-- The SELECT adds the file's details (name, line number, last change) next to
-- each line. Columns not listed (loaded_at) get their default value.
COPY INTO PNEUMA_LINES (source_file, line_number, line, file_last_modified)
FROM (
    SELECT
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER,
        $1,
        METADATA$FILE_LAST_MODIFIED
    FROM @PNEUMA_STAGE
)
FILE_FORMAT = (FORMAT_NAME = 'PNEUMA_LINE_FORMAT')
PATTERN     = '.*[.]csv([.]gz)?'
ON_ERROR    = ABORT_STATEMENT;   -- any bad line stops the whole load; nothing half-loaded
