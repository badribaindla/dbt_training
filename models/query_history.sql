    select
            dateadd(
                seconds,
                (queued_overload_time / 1000),
                start_time
            ) as usage_at,
            row_number() over(
                partition by warehouse_name
                order by
                    usage_at
            ) as start_ordinal,
            + 1 as type,
            q.*
        from
            "SNOWFLAKE"."ACCOUNT_USAGE"."QUERY_HISTORY" q
        where
            TO_DATE(start_time) BETWEEN CURRENT_DATE()-30
            AND CURRENT_DATE()
            and query_type in (
                'COPY',
                'INSERT',
                'MERGE',
                'UNLOAD',
                'RECLUSTER',
                'SELECT',
                'DELETE',
                'CREATE_TABLE_AS_SELECT',
                'UPDATE'
            )
            and cluster_number is not null
            and warehouse_name is not null
            and warehouse_name not like '%COMPUTE_SERVICE%'