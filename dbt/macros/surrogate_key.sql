{#
    Build one key column out of several columns by hashing them together.
    Same formula as dbt_utils.generate_surrogate_key, so keys match the old
    Postgres project, without needing the dbt_utils package.

    Usage:  {{ surrogate_key(['source_file', 'track_id']) }} as track_sk
#}
{% macro surrogate_key(columns) -%}
    md5(
        {%- for col in columns %}
        coalesce(cast({{ col }} as varchar), '_dbt_utils_surrogate_key_null_')
        {%- if not loop.last %} || '-' || {% endif %}
        {%- endfor %}
    )
{%- endmacro %}
