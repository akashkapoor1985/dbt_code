{% macro list_columns_with_type(table_name, schema_name='PUBLIC', database_name=target.database) %}

{# Get the table relation #}
{% set relation = adapter.get_relation(
        database=database_name,
        schema=schema_name,
        identifier=table_name
    ) %}

{# Get columns #}
{% set cols = adapter.get_columns_in_relation(relation) %}
{% set col_info = [] %}

{% for col in cols %}
    {%- do col_info.append(col.name ~ ' (' ~ col.data_type ~ ')') -%}
{% endfor %}

{# Convert to comma-separated string #}
{% set output = col_info | join(', ') %}

{# Log to job log #}
{{ log("Columns and data types for table " ~ schema_name ~ "." ~ table_name ~ ": " ~ output, info=True) }}

{# Return for CLI visibility as well #}
{{ return(output) }}

{% endmacro %}
