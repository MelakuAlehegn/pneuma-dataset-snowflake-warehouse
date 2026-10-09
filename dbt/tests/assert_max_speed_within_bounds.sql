/*
    No vehicle on a city street should reach 250 km/h. If one does, the units
    are wrong, the split is misreading values, or there's a real outlier worth
    a look. Returns offending vehicles; zero rows = pass.
*/
select
    track_sk,
    vehicle_type,
    max_speed_kmh
from {{ ref('dim_track') }}
where max_speed_kmh > 250
