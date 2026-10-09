{#
    One row per vehicle type found in the data (Car, Bus, ...).
#}

with types as (

    select distinct vehicle_type
    from {{ ref('stg_pneuma_tracks') }}
    where vehicle_type is not null

)

select
    {{ surrogate_key(['vehicle_type']) }}  as vehicle_type_sk,
    vehicle_type                           as vehicle_type_name

from types
