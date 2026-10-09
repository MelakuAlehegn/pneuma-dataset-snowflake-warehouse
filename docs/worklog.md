# Worklog

Short notes on what was done in each step, plus the "why" behind key choices.

## Step 1 · Platform foundation (done 2026-10-07)

**What was built**
- Snowflake CLI (`snow`) set up on the laptop, logging in with a key pair. Keys live in `~/.snowflake/`, never in the repo.
- Three job roles: `PNEUMA_LOADER`, `PNEUMA_TRANSFORMER`, `PNEUMA_ANALYST`, all placed under SYSADMIN.
- Three XS warehouses, one per kind of work: `LOAD_WH`, `TRANSFORM_WH`, `ANALYST_WH` (the last one stops any query after 60s).
- Two identical databases, `PNEUMA_DEV` and `PNEUMA_PROD`, each with schemas `RAW`, `STAGING`, `INTERMEDIATE`, `MARTS`, `SEMANTIC`, `APP`, `OPS` (all managed access).
- Permission bundles inside each database (`RAW_R`, `RAW_RW`, `TRANSFORM_RW`, `MARTS_R`), handed to the job roles in one file (`04_access.sql`).
- `PNEUMA_ANALYST` gets read-only access to prod `MARTS` and Cortex. That's all it gets.
- Checks: `99_verify.sql` (things that should work) and `99_verify_blocked.sh` (6 things that should be blocked). All pass.

**Files:** `snowflake/setup/01–05, 99_*`, run order in the README.

**Why notes**
- **SYSADMIN runs the object scripts.** Snowflake splits admin work: USERADMIN makes roles, SYSADMIN makes objects (and owns them), ACCOUNTADMIN is kept for account-wide settings only.
- **Secondary roles.** Snowsight can switch on all your roles at once in the background, so `USE ROLE X` alone doesn't prove role X can do something. Turn them off with `USE SECONDARY ROLES NONE` when testing permissions.
- **"Does not exist" can mean "not allowed".** When a role has no access to an object, Snowflake usually says the object doesn't exist instead of "permission denied", so it never reveals what's there.

## Step 2 · Load the raw file (done 2026-10-08)

**What was built**
- In `PNEUMA_DEV.RAW`: an internal stage `PNEUMA_STAGE`, a file format `PNEUMA_LINE_FORMAT` that reads each line as one value, and the table `PNEUMA_LINES`.
- `20181101_d1_0800_0830.csv` uploaded to the stage (gzipped on the way) and loaded: 785 rows, one per vehicle, longest line ~1.18M characters.
- Each row keeps the untouched line plus the file name, line number and load time.
- Local copy of the file lives in `data/` (git-ignored).

**Files:** `snowflake/ingest/01_raw_objects.sql`, `02_load.sql`, `99_check.sql`.

**Why notes**
- **Load lines unsplit.** Every vehicle line has a different number of values, so RAW keeps them as-is and dbt does the splitting. RAW stays an exact copy of the source.
- **Stage first, then table.** Upload puts the file in a stage (a file area); `COPY INTO` turns it into table rows. Two separate moves.
- **Re-running a load is safe.** Snowflake remembers which files it loaded into a table (64 days) and skips them.
- **Not everything needs a warehouse.** Creating objects and uploading files use none; `COPY INTO` and queries do.

## Step 3a · dbt running inside Snowflake (done 2026-10-08)

**What was built**
- `dbt/` project: `dbt_project.yml`, `profiles.yml` (targets `dev` → `PNEUMA_DEV`, `prod` → `PNEUMA_PROD`), a schema-naming macro, the source `RAW.PNEUMA_LINES`.
- First model `STAGING.stg_pneuma_tracks` (view): the 4 vehicle values from each line. 4 tests pass; counts match the file (Car 443, Motorcycle 153, Taxi 137, Medium Vehicle 30, Bus 20, Heavy Vehicle 2).
- Project stored in Snowflake as `PNEUMA_DEV.OPS.PNEUMA_DBT`; transformer role allowed to create dbt projects in `OPS`.

**Why notes**
- **dbt runs inside Snowflake.** `snow dbt deploy` uploads the code as a versioned object; `snow dbt execute` runs it on Snowflake's side. No local dbt install, no passwords in `profiles.yml`.
- **Flag order matters in `snow dbt execute`.** Snowflake options go before the project name; everything after it goes to dbt.
- **Database = environment.** Same schema names in dev and prod; the dbt target only switches the database.
- **A view stores nothing.** Its logic runs each time it's queried.

## Step 3b · Split lines into tracks and points (done 2026-10-08)

**What was built**
- `base_pneuma_lines` (ephemeral, shared): cleans each line, reads recording date / drone / time window from the file name, pulls out the 4 vehicle values.
- `stg_pneuma_tracks` (view): one row per vehicle, now with `track_sk`, `point_count`, `recording_date`, `drone_id`, `window_start`, `window_end`.
- `stg_pneuma_trajectory_points` (table): 1,239,475 points from 785 vehicles, with a real clock time `recorded_at`. Builds in about a minute on XS.
- `surrogate_key` macro (same keys as dbt_utils, no package needed) and tests: unique keys, every point belongs to a track, every line is 4 + 6×N values, every vehicle has exactly its expected number of points.

**Finding:** data in `20181101_d1_0800_0830` runs 08:00:38 → 08:14:48, not to 08:30. `window_end` is the planned end, not the actual one. Say so in the semantic model.

**Why notes**
- **Don't drag big values through row-multiplying joins.** The first version copied each vehicle's whole array (up to ~1 MB) onto every one of its points. It ran for minutes and had to be cancelled. Cutting the line into small rows (`SPLIT_TO_TABLE`) and grouping back finished in about a minute.
- **Heavy staging can be a table.** "Staging = views" is a default, not a rule. The points split is expensive and everything reads it, so it's built once per run.
- **Clock time comes from the file name.** pNEUMA only stores seconds since the start; the date and start time are in the file name.
- **Every warehouse gets a query time limit.** The default is 2 days. Now LOAD_WH 30 min, TRANSFORM_WH 15 min, ANALYST_WH 1 min. Settings are applied with `ALTER` (not inside `CREATE IF NOT EXISTS`, which skips existing warehouses). If limits are set at several levels (account, user, warehouse, session), the lowest wins.

## Step 3c · Intermediate and mart models (done 2026-10-08)

**What was built**
- Intermediate: `int_trajectory_points_with_deltas` (change since previous point, speed band; ephemeral) and `int_track_kinematics` (per-vehicle summary; table).
- Marts in `PNEUMA_DEV.MARTS`: `dim_vehicle_type` (6), `dim_track` (785, now with recording date, drone, window, first/last seen time), `fct_trajectory_points` (1,239,475, incremental), `agg_speed_by_vehicle_type` (6).
- `stg_pneuma_trajectory_points` and `fct_trajectory_points` are incremental: a run only processes newly loaded lines. `--full-refresh` rebuilds from scratch.
- Own `in_range` generic test replaces dbt_expectations; old bounds and both custom tests ported. No dbt packages needed.
- Sanity check: Motorcycle fastest (avg 22.6 km/h), Medium Vehicle slowest (8.6); type counts sum to all points.

**Why notes**
- **No packages, no internet access needed.** The old project only used dbt_utils for keys and dbt_expectations for range checks; both are a few lines of our own code. Fewer moving parts, nothing to download inside Snowflake.
- **Use Snowflake built-ins.** `HAVERSINE()` replaces the custom macro (it returns km, so ×1000); `COUNT_IF` replaces Postgres's `count(*) filter (where …)`.
- **Make the heavy step incremental.** The expensive split is in staging, so incremental there saves the most; the fact table is incremental too.
