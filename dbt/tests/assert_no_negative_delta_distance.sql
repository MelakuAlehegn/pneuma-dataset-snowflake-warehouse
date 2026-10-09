/*
    Distance between two points can't be negative. If it is, the distance
    calculation is broken. Returns offending points; zero rows = pass.
*/
select
    trajectory_point_sk,
    track_sk,
    delta_distance_m
from {{ ref('fct_trajectory_points') }}
where delta_distance_m < 0
