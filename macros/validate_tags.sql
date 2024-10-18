{% macro validate_column_tags(model_name) %}
  {% set allowed_tags = var('allowed_tags', []) %}
  {% set model = ref(model_name) %}
  {% set columns = dbt_utils.get_columns_in_relation(model) %}
  
  {% set disallowed_tags = [] %}
  
  -- Iterate over each column in the model
  {% for column in columns %}
    {% set column_meta = column.meta %}
    
    -- Check if the column has tags
    {% if column_meta is not none and 'tags' in column_meta %}
      {% set column_tags = column_meta['tags'] %}
      
      -- Compare each tag against allowed_tags
      {% for tag in column_tags %}
        {% if tag not in allowed_tags %}
          {% do disallowed_tags.append({
            'column': column.name,
            'tag': tag
          }) %}
        {% endif %}
      {% endfor %}
    {% endif %}
  {% endfor %}
  
  -- Log the disallowed tags for debugging
  {% if disallowed_tags | length > 0 %}
    {{ log("Disallowed tags found:", info=True) }}
    {{ log(disallowed_tags, info=True) }}
    
    -- Raise an error to fail the build
    {% for item in disallowed_tags %}
      {{ exceptions.raise_compiler_error("Tag '" ~ item.tag ~ "' is not allowed on column '" ~ item.column ~ "' in model '" ~ model_name ~ "'") }}
    {% endfor %}
  {% else %}
    {{ log("No disallowed tags found for model '" ~ model_name ~ "'.", info=True) }}
  {% endif %}
{% endmacro %}
