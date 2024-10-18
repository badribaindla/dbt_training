-- tests/tag_validation.sql

{{ 
    config(
        materialized='test'
    ) 
}}

{% set valid_tags = ['public', 'internal', 'confidential', 'restricted', 'mission_critical'] %}
{% set invalid_tags = [] %}

-- Log the incoming tags for debugging
{% do log("Incoming tags: " ~ tags | join(', '), info=True) %}

{% if tags is none or tags | length == 0 %}
    {% do log("No tags provided. Skipping validation.", info=True) %}
{% else %}
    {% for tag in tags %}
        {% if tag not in valid_tags %}
            {% do invalid_tags.append(tag) %}
        {% endif %}
    {% endfor %}
{% endif %}

{% if invalid_tags | length > 0 %}
    {{ exceptions.raise_compiler_error(
        "Build failed: Invalid tags found: " ~ invalid_tags | join(', ')
    ) }}
{% endif %}

select 1
