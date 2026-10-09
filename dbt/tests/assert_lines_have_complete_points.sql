/*
    Every raw line must be 4 vehicle values followed by whole points of 6
    values each. A line with leftover values means the file is damaged or the
    split is wrong. Returns the bad lines; zero rows = pass.
*/
select
    source_file,
    track_id,
    field_count
from {{ ref('base_pneuma_lines') }}
where mod(field_count - 4, 6) != 0
