{{ config(materialized='ephemeral') }}

{#
    Shared first pass over the raw lines, used by both staging models.
    Ephemeral: not stored anywhere, dbt pastes it into the models that use it.

    Does three things:
      1. cleans each line (drops the trailing "; ")
      2. reads the recording details out of the file name
      3. pulls out the 4 vehicle values at the start of the line

    File name pattern:  20181101_d1_0800_0830.csv
                        date     drone start end   (times are local Athens time)
#}

with source as (

    select * from {{ source('pneuma', 'pneuma_lines') }}

),

cleaned as (

    select
        -- The stage stores files gzipped; drop the .gz so the name matches the original file.
        regexp_replace(source_file, '[.]gz$', '')               as source_file,

        -- Lines end with "; ", which would leave an empty last value. Strip it.
        regexp_replace(line, '[;\\s]+$', '')                    as line_clean,

        line_number,
        loaded_at

    from source

)

select
    source_file,

    -- recording details from the file name
    to_date(split_part(source_file, '_', 1), 'YYYYMMDD')                       as recording_date,
    split_part(source_file, '_', 2)                                            as drone_id,
    to_timestamp_ntz(
        split_part(source_file, '_', 1) || split_part(source_file, '_', 3),
        'YYYYMMDDHH24MI'
    )                                                                          as window_start,
    to_timestamp_ntz(
        split_part(source_file, '_', 1) || split_part(split_part(source_file, '_', 4), '.', 1),
        'YYYYMMDDHH24MI'
    )                                                                          as window_end,

    -- the 4 vehicle values
    trim(split_part(line_clean, ';', 1))::number                               as track_id,
    trim(split_part(line_clean, ';', 2))                                       as vehicle_type,
    trim(split_part(line_clean, ';', 3))::float                                as total_distance_m,
    trim(split_part(line_clean, ';', 4))::float                                as avg_speed_kmh,

    -- everything after the first 4 values is points, 6 values each
    regexp_count(line_clean, ';') + 1                                          as field_count,
    floor((regexp_count(line_clean, ';') + 1 - 4) / 6)::int                    as point_count,
    line_clean,

    line_number,
    loaded_at

from cleaned
