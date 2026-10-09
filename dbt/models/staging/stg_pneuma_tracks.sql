{#
    One row per vehicle per file: the vehicle values plus when and where
    (which drone) it was recorded. The points are in stg_pneuma_trajectory_points.
#}

with lines as (

    select * from {{ ref('base_pneuma_lines') }}

)

select
    {{ surrogate_key(['source_file', 'track_id']) }}  as track_sk,

    -- natural key
    source_file,
    track_id,

    -- vehicle
    vehicle_type,
    total_distance_m,
    avg_speed_kmh,
    point_count,

    -- recording
    recording_date,
    drone_id,
    window_start,
    window_end,

    -- audit
    line_number,
    loaded_at

from lines
