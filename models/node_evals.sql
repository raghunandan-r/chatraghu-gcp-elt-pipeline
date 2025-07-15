-- models/node_evals.sql
-- This model unnests the evaluations array to create one row per node evaluation.

{{ config(
    materialized='incremental',
    partition_by={
      "field": "timestamp_start",
      "data_type": "timestamp",
      "granularity": "day"
    },
    unique_key=['run_id', 'thread_id', 'turn_index', 'node_name']
) }}

SELECT
    t.run_id,
    t.thread_id,
    t.turn_index,
    t.timestamp_start,
    t.graph_version,
    eval.* EXCEPT (explanation)
FROM
    {{ source('staging_eval_results_raw', 'daily_load') }} AS t,
    UNNEST(t.evaluations) AS eval

{% if is_incremental() %}
WHERE t.timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %}