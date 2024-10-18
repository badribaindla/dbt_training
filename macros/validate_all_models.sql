{% macro validate_all_models() %}
  -- Get the database and schema
  {% set database = target.database %}
  {% set schema = target.schema %}

  -- Log the resolved database and schema
  {{ log("Resolved database: " ~ database, info=True) }}
  {{ log("Resolved schema: " ~ schema, info=True) }}

  -- Check if the values are correct
  {% if not database or not schema %}
    {{ exceptions.raise_compiler_error("Database or schema could not be resolved. Check your profile configuration.") }}
  {% endif %}
  
  -- Fetch all relations
  {% set relations = dbt_utils.get_relations_by_prefix(adapter, database, schema, '') %}
  
  -- Iterate through all models and apply both fixes and tag validation
  {% for model in relations %}
    
    {{ log("Checking model: " ~ model.identifier, info=True) }}

    -- Construct the SQL query explicitly
    {% set sql_query = """
    select distinct
        table_schema as table_schema,
        table_name as table_name,
        case table_type
            when 'BASE TABLE' then 'table'
            when 'EXTERNAL TABLE' then 'external'
            when 'MATERIALIZED VIEW' then 'materializedview'
            else lower(table_type)
        end as table_type
    from """ ~ database ~ ".information_schema.tables
    where table_schema ilike '" ~ schema ~ "'
      and table_name ilike 'DBT_POC%'
      and table_name not ilike 'dbt_bshahbaz'
    " %}
    
    -- Log the generated SQL query
    {{ log("Generated SQL: " ~ sql_query, info=True) }}

    -- Execute the query
    {% set results = run_query(sql_query) %}

    -- Log the results
    {{ log("Results: " ~ results, info=True) }}

    -- Now validate the tags after fixing the syntax
    {{ validate_column_tags(model.identifier) }}

  {% endfor %}
{% endmacro %}
