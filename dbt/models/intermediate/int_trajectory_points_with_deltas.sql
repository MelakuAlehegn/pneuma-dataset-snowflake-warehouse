{{ config(materialized='ephemeral') }}

{#
    Each point plus how it changed since the vehicle's previous point:
    time passed, speed change, distance moved, and a speed band.
    Ephemeral: not stored, dbt pastes it into fct_trajectory_points.
#}

with points as (

    select * from {{ ref('stg_pneuma_trajectory_points') }}

),

with_previous as (

    -- The previous point of the same vehicle (empty for its first point).
    select
        *,
        lag(speed_kmh)           over (partition by track_sk order by frame_idx) as prev_speed_kmh,
        lag(seconds_since_start) over (partition by track_sk order by frame_idx) as prev_seconds_since_start,
        lag(latitude)            over (partition by track_sk order by frame_idx) as prev_latitude,
        lag(longitude)           over (partition by track_sk order by frame_idx) as prev_longitude

    from points

)

select
    *,
    seconds_since_start - prev_seconds_since_start                       as delta_time_sec,
    speed_kmh - prev_speed_kmh                                           as delta_speed_kmh,

    -- Snowflake's built-in HAVERSINE returns kilometers; we want meters.
    haversine(prev_latitude, prev_longitude, latitude, longitude) * 1000 as delta_distance_m,

    case
        when speed_kmh < 1  then 'STOPPED'
        when speed_kmh < 10 then 'SLOW'
        when speed_kmh < 50 then 'NORMAL'
        else 'FAST'
    end                                                                  as speed_bucket

from with_previous
