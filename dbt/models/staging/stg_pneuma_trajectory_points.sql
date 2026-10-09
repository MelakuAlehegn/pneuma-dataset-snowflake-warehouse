{{
    config(
        materialized='incremental',
        unique_key='trajectory_point_sk',
        incremental_strategy='merge'
    )
}}

{#
    One row per recorded point per vehicle (a point every 0.04 seconds).

    Stored as a table, not a view: splitting ~1.2M points out of the raw lines
    is the heaviest step in the project. Incremental: each run only splits
    lines loaded since the last run, so adding a new file doesn't re-split
    the old ones. To rebuild from scratch: dbt build --full-refresh.

    How the split works:
      1. cut every line into one row per value (SPLIT_TO_TABLE numbers them 1, 2, 3, ...)
      2. skip the first 4 (vehicle values); from value 5 on, every 6 values are one point:
           point number   = (position - 5) / 6, rounded down
           which value    = (position - 5) mod 6  → 0 lat, 1 lon, 2 speed, 3 lon_acc, 4 lat_acc, 5 time
      3. group the 6 values of each point back into one row

    Why not keep the line as an array and read values by position? Because then
    every point row carries its vehicle's whole array (up to ~1 MB) with it,
    and the query moves tens of GB instead of ~90 MB. Small rows are cheap.
#}

with lines as (

    select source_file, track_id, window_start, loaded_at, line_clean
    from {{ ref('base_pneuma_lines') }}

    {% if is_incremental() %}
    -- Only lines loaded after the newest point already in this table.
    where loaded_at > (select coalesce(max(loaded_at), '1900-01-01'::timestamp_ltz) from {{ this }})
    {% endif %}

),

point_values as (

    select
        lines.source_file,
        lines.track_id,
        lines.window_start,
        lines.loaded_at,
        floor((part.index - 5) / 6)::int     as frame_idx,
        mod(part.index - 5, 6)               as value_kind,
        trim(part.value)::float              as val

    from lines,
        lateral split_to_table(lines.line_clean, ';') as part
    where part.index > 4

),

points as (

    select
        source_file,
        track_id,
        frame_idx,
        window_start,
        loaded_at,

        max(case when value_kind = 0 then val end)  as latitude,
        max(case when value_kind = 1 then val end)  as longitude,
        max(case when value_kind = 2 then val end)  as speed_kmh,
        max(case when value_kind = 3 then val end)  as lon_acceleration_ms2,
        max(case when value_kind = 4 then val end)  as lat_acceleration_ms2,
        max(case when value_kind = 5 then val end)  as seconds_since_start

    from point_values
    group by source_file, track_id, frame_idx, window_start, loaded_at

)

select
    {{ surrogate_key(['source_file', 'track_id', 'frame_idx']) }}  as trajectory_point_sk,
    {{ surrogate_key(['source_file', 'track_id']) }}               as track_sk,

    -- natural key
    source_file,
    track_id,
    frame_idx,

    -- position
    latitude,
    longitude,

    -- movement
    speed_kmh,
    lon_acceleration_ms2,
    lat_acceleration_ms2,

    -- time: seconds into the recording, and the real clock time
    seconds_since_start,
    timestampadd(millisecond, round(seconds_since_start * 1000), window_start)  as recorded_at,

    -- audit
    loaded_at

from points
