/*
    Each vehicle must have exactly as many rows in stg_pneuma_trajectory_points
    as its line said it had points: none dropped, none invented.
    Returns the vehicles that don't match; zero rows = pass.
*/
with expected as (

    select track_sk, point_count
    from {{ ref('stg_pneuma_tracks') }}

),

actual as (

    select track_sk, count(*) as point_count
    from {{ ref('stg_pneuma_trajectory_points') }}
    group by track_sk

)

select
    expected.track_sk,
    expected.point_count          as expected_points,
    coalesce(actual.point_count, 0) as actual_points
from expected
left join actual
    on expected.track_sk = actual.track_sk
where expected.point_count != coalesce(actual.point_count, 0)
