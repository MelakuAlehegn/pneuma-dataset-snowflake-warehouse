{#
    Fails for any value outside [min_value, max_value]. Empty values are ignored.
    Replaces dbt_expectations.expect_column_values_to_be_between, so we don't
    need that package.

    Usage in YAML:
        data_tests:
          - in_range:
              min_value: 0
              max_value: 200
#}
{% test in_range(model, column_name, min_value, max_value) %}

select {{ column_name }}
from {{ model }}
where {{ column_name }} is not null
  and ({{ column_name }} < {{ min_value }} or {{ column_name }} > {{ max_value }})

{% endtest %}
