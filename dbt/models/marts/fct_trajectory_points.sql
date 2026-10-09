{{
    config(
        materialized='incremental',
        unique_key='trajectory_point_sk',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

{#
    One row per recorded point per vehicle. The main fact table.

    Incremental: the first run builds everything; later runs only add points
    loaded since the last run, merged on trajectory_point_sk so nothing is
    ever added twice. To rebuild from scratch: dbt build --full-refresh.

    Why the "previous point" values are still right on later runs: a file is
    loaded in one go, so every point of a vehicle arrives together.
#}

with points as (

    select * from {{ ref('int_trajectory_points_with_deltas') }}

    {% if is_incremental() %}
    where loaded_at > (select coalesce(max(loaded_at), '1900-01-01'::timestamp_ltz) from {{ this }})
    {% endif %}

)

select
    trajectory_point_sk,
    track_sk,

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

    -- time
    seconds_since_start,
    recorded_at,

    -- change since the previous point
    delta_time_sec,
    delta_speed_kmh,
    delta_distance_m,
    speed_bucket,

    -- audit
    loaded_at

from points
