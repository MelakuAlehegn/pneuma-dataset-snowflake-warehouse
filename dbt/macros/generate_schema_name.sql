{#
    Use each model's schema name exactly as configured (STAGING, MARTS, ...).

    By default dbt glues the target schema in front, e.g. STAGING_MARTS. We
    don't need that: environments are separated by database (PNEUMA_DEV vs
    PNEUMA_PROD), so the schema names can be the same in both.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
