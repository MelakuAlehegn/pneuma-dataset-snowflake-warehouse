{#
    One row per vehicle: what it is, when and by which drone it was recorded,
    and a summary of how it moved. Links to dim_vehicle_type, so the fact
    table only needs to link here.
#}

with tracks as (

    select * from {{ ref('stg_pneuma_tracks') }}

),

kinematics as (

    select * from {{ ref('int_track_kinematics') }}

),

vehicle_types as (

    select * from {{ ref('dim_vehicle_type') }}

)

select
    tracks.track_sk,
    vehicle_types.vehicle_type_sk,

    -- natural key
    tracks.source_file,
    tracks.track_id,

    -- vehicle
    tracks.vehicle_type,

    -- recording
    tracks.recording_date,
    tracks.drone_id,
    tracks.window_start,
    tracks.window_end,

    -- as reported in the source file
    tracks.total_distance_m,
    tracks.avg_speed_kmh,

    -- computed from the points
    kinematics.point_count,
    kinematics.first_seen_at,
    kinematics.last_seen_at,
    kinematics.duration_sec,
    kinematics.min_speed_kmh,
    kinematics.max_speed_kmh,
    kinematics.stopped_point_count,

    -- audit
    tracks.loaded_at

from tracks
left join kinematics
    on tracks.track_sk = kinematics.track_sk
left join vehicle_types
    on tracks.vehicle_type = vehicle_types.vehicle_type_name
