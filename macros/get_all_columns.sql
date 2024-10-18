{% macro get_all_columns() %}
    {% set all_columns = [] %}

    {% for model in graph.nodes.values() %}
        {% if model.resource_type == 'model' %}
            {% set model_name = model.name %}
            {% set columns = model.columns %}

            {% if columns is not none and columns | length > 0 %}
                {% for column in columns %}
                    {% set tags = column.meta.tags | default([]) %}
                    
                    {# Ensure tags are converted to a string if they are a list #}
                    {% if tags is iterable and tags is not string %}
                        {% set tags_str = tags | join(', ') %}
                    {% else %}
                        {% set tags_str = tags %}
                    {% endif %}

                    {% set column_info = {
                        'model_name': model_name,
                        'column_name': column.name,
                        'description': column.description,
                        'data_type': column.data_type,
                        'tags': tags_str
                    } %}
                    {% do all_columns.append(column_info) %}
                {% endfor %}
                {{ log("Model '" ~ model_name ~ "' collected columns: " ~ (columns | map(attribute='name') | join(', ')), info=True) }}
            {% else %}
                {{ log("Model '" ~ model_name ~ "' has no columns.", info=True) }}
            {% endif %}
        {% endif %}
    {% endfor %}

    {{ log("Total columns collected: " ~ all_columns | length, info=True) }}
    
    {{ return(all_columns) }}
{% endmacro %}
