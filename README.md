# pNEUMA on Snowflake

Drone traffic data from downtown Athens (the pNEUMA dataset), turned into a
Snowflake data warehouse with dbt, and made queryable in plain English through
Cortex Analyst and a Streamlit app.

This combines and upgrades two earlier projects: a Postgres + dbt warehouse
and a separate natural-language-to-SQL app.

> Work in progress. See [docs/worklog.md](docs/worklog.md) for what has been done so far.

## How it fits together

```
pNEUMA CSV files
      │  load
      ▼
RAW ──dbt──► STAGING ──► INTERMEDIATE ──► MARTS
                                            │
                     semantic model (YAML) ─┤
                                            ▼
                                     Cortex Analyst ──► Streamlit app
```

Two databases, `PNEUMA_DEV` and `PNEUMA_PROD`, hold the same layout.

## Repo layout

```
snowflake/setup/   one-time account setup: roles, warehouses, databases, permissions
snowflake/ingest/  loading pNEUMA files into RAW
dbt/               dbt project (runs inside Snowflake)
docs/              worklog and design notes
```

## Setting up a Snowflake account

Needs the [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index)
(`snow`) with a working connection. From the repo root, run in this order:

```bash
snow sql -f snowflake/setup/01_roles.sql                           # USERADMIN: the three job roles
snow sql -f snowflake/setup/02_warehouses.sql                      # SYSADMIN: one warehouse per kind of work
snow sql -f snowflake/setup/03_database.sql -D db_name=PNEUMA_DEV  # SYSADMIN: database, schemas, permission bundles
snow sql -f snowflake/setup/03_database.sql -D db_name=PNEUMA_PROD
snow sql -f snowflake/setup/04_access.sql                          # SYSADMIN: give job roles their bundles
snow sql -f snowflake/setup/05_cortex.sql                          # ACCOUNTADMIN: Cortex access for the app role

snow sql -f snowflake/setup/99_verify.sql                          # things that should work
bash snowflake/setup/99_verify_blocked.sh                          # things that should be blocked
```

Every file is safe to re-run.

## Loading data

```bash
snow sql -f snowflake/ingest/01_raw_objects.sql -D db_name=PNEUMA_DEV        # stage, file format, table
snow stage copy data/20181101_d1_0800_0830.csv @PNEUMA_DEV.RAW.PNEUMA_STAGE --role PNEUMA_LOADER
snow sql -f snowflake/ingest/02_load.sql -D db_name=PNEUMA_DEV               # COPY INTO RAW.PNEUMA_LINES
snow sql -f snowflake/ingest/99_check.sql -D db_name=PNEUMA_DEV              # row counts and load history
```

## Running dbt

The dbt project is stored in Snowflake as an object (`OPS.PNEUMA_DBT`) and runs there.

```bash
# upload the current dbt/ folder (each deploy creates a new version)
snow dbt deploy PNEUMA_DBT --source dbt --profiles-dir dbt \
    --database PNEUMA_DEV --schema OPS --role PNEUMA_TRANSFORMER

# build models and run tests
# (Snowflake options go BEFORE the project name; everything after it is passed to dbt)
snow dbt execute --database PNEUMA_DEV --schema OPS --role PNEUMA_TRANSFORMER --warehouse TRANSFORM_WH \
    PNEUMA_DBT build --target dev
```
