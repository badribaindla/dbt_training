    with wh_metering as (
            SELECT
                warehouse_name,
                ROUND(SUM(credits_used_compute), 0) AS compute_credits_used,
                ROUND(SUM(credits_used_cloud_services), 0) cloud_services_credits_used
            FROM
                {{source('ORGANIZATION_USAGE','WAREHOUSE_METERING_HISTORY')}}
            WHERE
                TO_DATE(START_TIME) BETWEEN CURRENT_DATE()-30
                AND CURRENT_DATE()
            GROUP BY
                1
        ),
        wh_kpis as (
            select
                job.warehouse_name,
                job.warehouse_size,
                avg(query_load_percent) as avg_pct_warehouse_used,
                percentile_cont(.90) within group (
                    order by
                        (query_load_percent)
                ) as p90_wh_used,
                count(distinct job.query_id) as job_count,
                sum(job.queued_overload_time) / 1000 as total_queue_time,
                sum(total_elapsed_time) / 1000 as total_duration,
                avg(queued_overload_time / total_elapsed_time) as avg_pct_total_queued,
                avg(execution_time) / 1000 as avg_xp_duration,
                avg(total_elapsed_time) / 1000 as avg_total_dur,
                avg(bytes_spilled_to_remote_storage) / power(1024, 3) as remote_temp_space_usage_gb,
                sum(
                    case
                        when bytes_spilled_to_remote_storage is not null then 1
                        else 0
                    end
                ) as num_jobs_remote_spilling,
                sum(
                    case
                        when bytes_spilled_to_remote_storage is not null then 1
                        else 0
                    end
                ) / job_count as pct_jobs_spilled_remote
            from
                {{source('ACCOUNT_USAGE','QUERY_HISTORY')}} job
            where
                1 = 1
                and job.cluster_number is not null
                and TO_DATE(job.start_time) BETWEEN CURRENT_DATE()-30
                AND CURRENT_DATE()
            group by 1,2
        ),
        cat_scores as (
            select
                warehouse_name,
                warehouse_size,
                case
                    when p90_wh_used < 100 then 100::number
                end as p90_wh_used_score --if 90 percent of the jobs dont use the full warehouse, pad the score to the to small side
    ,
                (100 - (avg_pct_warehouse_used))::number as avg_wh_used_score --add one point for each avg pct below 100 used
    ,
                case
                    when avg_xp_duration < 10 then ((60 - avg_xp_duration) * 2)::number
                    else (60 - avg_xp_duration)::number
                end as xp_dur_score --subtract a point for each second over 60, --add a point for each second below 60
    ,
                -(pct_jobs_spilled_remote * 100 * 2)::number as pct_jobs_spilling_score --add two points for each percentage of jobs with spilling to remote
            from
                wh_kpis
        ),
        wh_scoring as (
            select
                piv.warehouse_name,
                piv.warehouse_size,
                sum(piv.score) as warehouse_size_score,
                wh_metering.compute_credits_used
            from
                cat_scores unpivot(
                    score for scores in (
                        p90_wh_used_score,
                        avg_wh_used_score,
                        xp_dur_score,
                        pct_jobs_spilling_score
                    )
                ) piv
                left join wh_metering on piv.warehouse_name = wh_metering.warehouse_name
            group by
                piv.warehouse_name,
                piv.warehouse_size,
                wh_metering.compute_credits_used
            order by
                abs(warehouse_size_score) desc
        ),
        cte_qh as (
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
                {{source('ACCOUNT_USAGE','QUERY_HISTORY')}} q
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
            union all
            select
                end_time as usage_at,
                null as start_ordinal,
                -1 as type,
                q.*
            from
                {{source('ACCOUNT_USAGE','QUERY_HISTORY')}} q
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
        ),
        cte_concurrency_prep as (
            select
                row_number() over(
                    partition by warehouse_name
                    order by
                        usage_at,
                        type
                ) as start_or_end_ordinal,
                *
            from
                cte_qh
        ),
        credits_30_days as (
            select
                warehouse_name,
                sum(credits_used) as credits_used_30_days
            from
                {{source('ORGANIZATION_USAGE','WAREHOUSE_METERING_HISTORY')}}
            where
                TO_DATE(start_time) BETWEEN CURRENT_DATE()-30
                AND CURRENT_DATE()
            group by
                1
        ),
        wh_utilization as (
            select
                distinct warehouse_name,
                credits_used_30_days,
                avg_highwater_mark_of_concurrency_per_minute,
                highwater_mark_of_concurrency,
                'Warehouse ' || warehouse_name || ' has concurrency highwater mark of AVG: ' || avg_highwater_mark_of_concurrency_per_minute || ' MAX: ' || highwater_mark_of_concurrency || ' and consumed ' || credits_used_30_days || ' credits in the last 30 days and is potentially underutilized' finding
            from
                (
                    select
                        j.warehouse_name,
                        credits_used_30_days,
                        date_trunc(minute, usage_at) as usage_minute,
                        max(max(2 * start_ordinal - start_or_end_ordinal)) over(partition by j.warehouse_name) as highwater_mark_of_concurrency,
                        avg(max(2 * start_ordinal - start_or_end_ordinal)) over(partition by j.warehouse_name) as avg_highwater_mark_of_concurrency_per_minute
                    from
                        cte_concurrency_prep j
                        left join credits_30_days c on j.warehouse_name = c.warehouse_name
                    where
                        type = 1
                    group by
                        1,
                        2,
                        3 qualify avg_highwater_mark_of_concurrency_per_minute < 5
                )
        )
    select
        CURRENT_DATE()-30 AS JOB_START_DATE,
        CURRENT_DATE() AS JOB_END_DATE,
        coalesce(
            wh_scoring.warehouse_name,
            wh_utilization.warehouse_name
        ) warehouse_name,
        coalesce(avg_highwater_mark_of_concurrency_per_minute, 0) avg_highwater_mark_of_concurrency_per_minute,
        coalesce(highwater_mark_of_concurrency, 0) highwater_mark_of_concurrency,
        coalesce(warehouse_size_score, 0) warehouse_size_score
    --    coalesce(
    --        wh_scoring.compute_credits_used,
    --        wh_utilization.credits_used_30_days
    --    ) credits_used_30_days
    from
        wh_scoring full
        outer join wh_utilization on wh_utilization.warehouse_name = wh_scoring.warehouse_name
    order by
        abs(warehouse_size_score) desc,
        avg_highwater_mark_of_concurrency_per_minute