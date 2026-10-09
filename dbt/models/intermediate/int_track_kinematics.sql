{{ config(materialized='table') }}

{#
    One row per vehicle: a summary of all its points. dim_track uses this.
    Stored as a table: it reads all 1.2M points but the result is tiny
    (one row per vehicle), so compute it once per run.
#}

with points as (

    select * from {{ ref('stg_pneuma_trajectory_points') }}

)

select
    track_sk,

    count(*)                                            as point_count,

    min(seconds_since_start)                            as first_seen_sec,
    max(seconds_since_start)                            as last_seen_sec,
    max(seconds_since_start) - min(seconds_since_start) as duration_sec,

    min(recorded_at)                                    as first_seen_at,
    max(recorded_at)                                    as last_seen_at,

    min(speed_kmh)                                      as min_speed_kmh,
    max(speed_kmh)                                      as max_speed_kmh,

    count_if(speed_kmh < 1)                             as stopped_point_count

from points
group by track_sk
