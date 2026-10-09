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

## Step 4a · Prod filled, semantic stage ready (done 2026-10-09)

**What was built**
- `PNEUMA_PROD` loaded (785 lines) and built with dbt `--target prod`; prod has its own dbt project object in `PNEUMA_PROD.OPS`.
- Each database has a stage `SEMANTIC.SEMANTIC_MODELS` for Cortex Analyst YAML files (owned by SYSADMIN).
- New bundle `SEMANTIC_R` (read the YAML) given to the analyst role in prod; the transformer role can upload.
- Blocked checks now 7, all pass (analyst can't change semantic files).

**Why notes**
- **Dev and prod each have their own stage, table and dbt project.** Nothing is shared, so prod can be loaded and scheduled separately.
- **`-D name=value` fills `<% name %>` placeholders.** The CLI does this before sending the file; a missing value stops it before anything runs.

## Step 4b · First semantic model (done 2026-10-09)

**What was built**
- `semantic/pneuma_traffic.yaml`: two tables (`vehicles` = DIM_TRACK, `positions` = FCT_TRAJECTORY_POINTS), their columns, synonyms, ready-made calculations, the join between them, and general instructions. Uploaded to `@PNEUMA_PROD.SEMANTIC.SEMANTIC_MODELS` and tested in Snowsight as `PNEUMA_ANALYST`.

**Test results**
| Question | Result |
|---|---|
| Vehicles of each type | Correct (Car 443 … Heavy Vehicle 2) |
| Average speed by type | Correct target: Motorcycle 22.6 … Medium Vehicle 8.6 |
| What happened after 08:20? | Right SQL, empty result (data ends 08:14:48), no explanation |
| Average speed minute by minute | Empty: it kept the "after 08:20" filter from the previous question |
| Time buses spent stopped | Expected ≈ 722 s (12 min), 42% of bus time |

**To handle in 4c (semantic model)**
- Remove the "say when there's no data" instruction. Cortex only writes SQL and never sees results.
- State the covered time range (2018-11-01, 08:00:38–08:14:48, drone d1) in the model description.
- Instruct it to summarize (per minute, per type, …) instead of listing raw readings, unless asked.
- Add verified queries: data coverage, vehicles by type, average speed by type, top 5 by top speed, bus time stopped, average speed per minute.

**To handle in step 5 (app)**
- When a query returns no rows, say so and show the covered time range.
- Show the generated SQL and the filters applied.
- "New conversation" button: follow-up questions carry earlier filters along.

**To handle in evals**
- Ask each eval question in a fresh conversation.

**Why notes**
- **Cortex Analyst writes SQL; it doesn't see the answer.** Anything about the results (empty, too many rows) has to be handled by the app.
- **Chats are conversations.** Each question is read in the context of earlier ones, which helps follow-ups and surprises independent questions.

## Step 4c · Semantic model improved (done 2026-10-09)

**What changed**
- Description states what the data covers (d1, 2018-11-01, 08:00:38–08:14:48). Update it by hand when new recordings are loaded.
- Instructions: "time stopped" means seconds; summarize instead of listing raw readings (max 100 rows); removed the "say when there's no data" line.
- 6 verified queries (4 marked as starter questions): data coverage, vehicles by type, average speed by type, top 5 by top speed, bus time stopped, average speed per minute.

**Test results:** all correct in fresh chats, including new wordings (taxi average speed 18.7, 153 motorcycles, stopped share by type with Medium Vehicle highest at 57.7%, minute-by-minute for buses only). "After 08:20" still returns an empty table with no explanation; that's for the app (step 5).

**Why notes**
- **Verified queries teach by example.** Cortex follows their patterns for similar questions, not only identical ones.
- **Describe the data's limits in the model,** but don't expect Cortex to react to results; it never sees them.
