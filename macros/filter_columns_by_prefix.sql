{% macro filter_columns_by_prefix(table_name, prefix, schema_name='PUBLIC', database_name=target.database) %}

{# 1️⃣ Call the existing macro to get all columns with types #}
{% set all_columns_output = list_columns_with_type(table_name=table_name, schema_name=schema_name, database_name=database_name) %}

{# The existing macro returns a comma-separated string like: "COL1 (VARCHAR), COL2 (NUMBER), ..." #}
{% set all_columns_list = all_columns_output.split(', ') %}

{# 2️⃣ Filter columns by prefix #}
{% set filtered_cols = [] %}
{% for col in all_columns_list %}
    {% set col_name = col.split(' (')[0] %}
    {% if col_name.startswith(prefix) %}
        {% do filtered_cols.append(col) %}
    {% endif %}
{% endfor %}

{# 3️⃣ Convert to string for logging #}
{% set output = filtered_cols | join(', ') %}
{{ log("Columns in table " ~ schema_name ~ "." ~ table_name ~ " filtered by prefix '" ~ prefix ~ "': " ~ output, info=True) }}

{# 4️⃣ Return for CLI #}
{{ return(output) }}

{% endmacro %}
