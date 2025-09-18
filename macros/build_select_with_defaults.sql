{% macro build_select_with_defaults(table_name, prefix, schema_name='PUBLIC', database_name='test_DB', mode='select') %}
    {# Get filtered columns with types using your existing macro #}
    {% set filtered_output = filter_columns_by_prefix(table_name=table_name, prefix=prefix, schema_name=schema_name, database_name=database_name) %}
    {% set filtered_list = filtered_output.split(', ') %}
    
    {% if execute %}
        {# Query to get default values from registry with better error handling #}
        {% set defaults_query %}
            SELECT 
                UPPER(TRIM(DATA_TYPE)) as DATA_TYPE,
                DEFAULT_VALUE,
                IDENTIFIER,
                UPPER(TRIM(TABLE_NAME)) as TABLE_NAME,
                COLUMN_NAME
            FROM {{ database_name }}.{{ schema_name }}.default_values_registry
            WHERE ACTIVE_FLAG = TRUE
            AND IDENTIFIER IN ('GLOBAL_DEFAULTS', 'TABLE_DEFAULTS')
            AND (
                (IDENTIFIER = 'GLOBAL_DEFAULTS') 
                OR 
                (IDENTIFIER = 'TABLE_DEFAULTS' AND UPPER(TRIM(TABLE_NAME)) = UPPER(TRIM('{{ table_name }}')))
            )
            ORDER BY IDENTIFIER DESC
        {% endset %}
        
        {% set defaults_result = run_query(defaults_query) %}
        
        {# Error handling for query execution #}
        {% if not defaults_result %}
            {{ log("WARNING: No results returned from default_values_registry. Using fallback defaults.", True) }}
        {% endif %}
        
        {# Create lookup dictionaries for defaults #}
        {% set global_defaults = {} %}
        {% set table_defaults = {} %}
        
        {% if defaults_result %}
            {% for row in defaults_result %}
                {% if row|length >= 5 %}
                    {% set data_type = row[0]|upper|trim %}
                    {% set default_value = row[1] %}
                    {% set identifier = row[2] %}
                    {% set registry_table_name = row[3] %}
                    {% set column_name = row[4] %}
                    
                    {% if identifier == 'GLOBAL_DEFAULTS' %}
                        {% set _ = global_defaults.update({data_type: default_value}) %}
                    {% elif identifier == 'TABLE_DEFAULTS' and registry_table_name|upper == table_name|upper %}
                        {% set _ = table_defaults.update({data_type: default_value}) %}
                    {% endif %}
                {% endif %}
            {% endfor %}
        {% endif %}
        
        {# Build SELECT with defaults #}
        {% set select_columns = [] %}
        
        {% for item in filtered_list %}
            {% set parts = item.split(' (') %}
            {% set column_name = parts[0] %}
            {% set full_data_type = parts[1].rstrip(')') %}
            
            {# Extract base data type (remove length/precision info) #}
            {% set base_data_type = full_data_type.split('(')[0]|trim %}
            
            {# Enhanced Snowflake data type mapping #}
            {% if 'CHARACTER VARYING' in full_data_type|upper %}
                {% set lookup_data_type = 'VARCHAR' %}
            {% elif full_data_type|upper|trim in ('TEXT', 'STRING') %}
                {% set lookup_data_type = full_data_type|upper|trim %}
            {% elif base_data_type|upper == 'NUMBER' %}
                {# More precise NUMBER type classification #}
                {% if '38,0' in full_data_type %}
                    {% if 'BIGINT' in global_defaults or 'BIGINT' in table_defaults %}
                        {% set lookup_data_type = 'BIGINT' %}
                    {% elif 'INTEGER' in global_defaults or 'INTEGER' in table_defaults %}
                        {% set lookup_data_type = 'INTEGER' %}
                    {% else %}
                        {% set lookup_data_type = 'NUMBER' %}
                    {% endif %}
                {% else %}
                    {% set lookup_data_type = 'NUMBER' %}
                {% endif %}
            {% elif base_data_type|upper == 'FLOAT' %}
                {# Handle FLOAT vs DOUBLE precision #}
                {% if 'DOUBLE' in full_data_type|upper %}
                    {% set lookup_data_type = 'DOUBLE' %}
                {% else %}
                    {% set lookup_data_type = 'FLOAT' %}
                {% endif %}
            {% else %}
                {% set lookup_data_type = base_data_type|upper|trim %}
            {% endif %}
            
            {# Determine default value: table-specific overrides global #}
            {% if table_defaults.get(lookup_data_type) %}
                {% set default_value = table_defaults.get(lookup_data_type) %}
                {% set source = "TABLE_DEFAULTS" %}
            {% elif global_defaults.get(lookup_data_type) %}
                {% set default_value = global_defaults.get(lookup_data_type) %}
                {% set source = "GLOBAL_DEFAULTS" %}
            {% else %}
                {% set default_value = "NULL" %}
                {% set source = "FALLBACK" %}
            {% endif %}
            
            {# Enhanced default value formatting for Snowflake #}
            {% if default_value == "NULL" or default_value is none or default_value == "" %}
                {% set formatted_default = "NULL" %}
            {% elif lookup_data_type in ('VARCHAR', 'CHAR', 'STRING', 'TEXT') %}
                {# Escape single quotes in string values #}
                {% set escaped_value = default_value|replace("'", "''") %}
                {% set formatted_default = "'" ~ escaped_value ~ "'" %}
            {% elif lookup_data_type in ('NUMBER', 'INTEGER', 'BIGINT', 'SMALLINT', 'DECIMAL', 'NUMERIC', 'FLOAT', 'DOUBLE') %}
                {# Validate numeric values #}
                {% set formatted_default = default_value %}
            {% elif lookup_data_type == 'BOOLEAN' %}
                {% if default_value|upper in ('TRUE', 'FALSE') %}
                    {% set formatted_default = default_value|upper %}
                {% else %}
                    {% set formatted_default = "FALSE" %}
                {% endif %}
            {% elif lookup_data_type == 'DATE' %}
                {% if default_value in ('01/01/1970', '1970-01-01') %}
                    {% set formatted_default = "'1970-01-01'::DATE" %}
                {% else %}
                    {% set formatted_default = "'" ~ default_value ~ "'::DATE" %}
                {% endif %}
            {% elif 'TIME' in lookup_data_type %}
                {% if 'TIMESTAMP' in lookup_data_type %}
                    {% if default_value in ('01/01/1970 00:00', '1970-01-01 00:00:00') %}
                        {% set formatted_default = "'1970-01-01 00:00:00'::TIMESTAMP_NTZ" %}
                    {% else %}
                        {% set formatted_default = "'" ~ default_value ~ "'::" ~ lookup_data_type %}
                    {% endif %}
                {% else %}
                    {% set formatted_default = "'" ~ default_value ~ "'::TIME" %}
                {% endif %}
            {% elif lookup_data_type == 'GEOGRAPHY' %}
                {% set formatted_default = "ST_GEOGFROMTEXT('" ~ default_value ~ "')" %}
            {% elif lookup_data_type in ('VARIANT', 'OBJECT', 'ARRAY') %}
                {% set formatted_default = "PARSE_JSON('" ~ default_value ~ "')" %}
            {% elif lookup_data_type == 'BINARY' %}
                {% set formatted_default = "NULL" %}
            {% else %}
                {% set formatted_default = "NULL" %}
                {{ log("WARNING: Unknown data type '" ~ lookup_data_type ~ "' for " ~ column_name ~ ", using NULL", True) }}
            {% endif %}
            
            {% set select_expr = "COALESCE(" ~ column_name ~ ", " ~ formatted_default ~ ") AS " ~ column_name %}
            {% set _ = select_columns.append(select_expr) %}
            
            {# Debug logging #}
            {{ log("Column: " ~ column_name ~ " | Type: " ~ lookup_data_type ~ " | Default: " ~ formatted_default ~ " | Source: " ~ source, True) }}
        {% endfor %}
        
        {# Generate final result based on mode #}
        {% if mode == 'select' %}
            {% set final_result = "SELECT\n    " ~ select_columns|join(',\n    ') %}
        {% elif mode == 'column_list' %}
            {% set final_result = select_columns|join(',\n    ') %}
        {% else %}
            {% set final_result = select_columns|join(',\n    ') %}
        {% endif %}
        
        {{ log("=== Generated SELECT with Registry Defaults ===", True) }}
        {{ log(final_result, True) }}
        {{ log("============================================", True) }}
        
        {{ return(final_result) }}
        
    {% else %}
        {{ return("-- Macro not executed during parsing") }}
    {% endif %}
{% endmacro %}