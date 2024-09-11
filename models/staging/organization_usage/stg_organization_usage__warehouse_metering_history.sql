with 

source as (

    select * from {{ source('organization_usage', 'warehouse_metering_history') }}

),

renamed as (

    select
        organization_name,
        account_name,
        region,
        service_type,
        start_time,
        end_time,
        warehouse_id,
        warehouse_name,
        credits_used,
        credits_used_compute,
        credits_used_cloud_services,
        account_locator

    from source

)

select * from renamed
