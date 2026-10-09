{#
    Speed statistics per vehicle type: one row per type. Pre-computed so
    common questions read 6 rows instead of 1.2M.
#}

with points as (

    select track_sk, speed_kmh from {{ ref('fct_trajectory_points') }}

),

tracks as (

    select track_sk, vehicle_type_sk from {{ ref('dim_track') }}

),

vehicle_types as (

    select vehicle_type_sk, vehicle_type_name from {{ ref('dim_vehicle_type') }}

)

select
    vehicle_types.vehicle_type_sk,
    vehicle_types.vehicle_type_name,

    count(*)                                                             as observation_count,

    avg(points.speed_kmh)                                                as avg_speed_kmh,
    min(points.speed_kmh)                                                as min_speed_kmh,
    max(points.speed_kmh)                                                as max_speed_kmh,
    stddev(points.speed_kmh)                                             as stddev_speed_kmh,

    percentile_cont(0.50) within group (order by points.speed_kmh)       as median_speed_kmh,
    percentile_cont(0.95) within group (order by points.speed_kmh)       as p95_speed_kmh

from points
inner join tracks
    on points.track_sk = tracks.track_sk
inner join vehicle_types
    on tracks.vehicle_type_sk = vehicle_types.vehicle_type_sk
group by vehicle_types.vehicle_type_sk, vehicle_types.vehicle_type_name
