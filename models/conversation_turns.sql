-- models/conversation_turns.sql
-- This model creates the main fact table with one row per conversation turn.

{{ config(
    materialized='incremental',
    partition_by = {
      "field": "timestamp_start",
      "data_type": "timestamp",
      "granularity": "day"
    },
    unique_key=['run_id', 'thread_id', 'turn_index'],
    on_schema_change='append_new_columns'
) }}

SELECT
    run_id,
    thread_id,
    turn_index,
    graph_version,
    timestamp_start,
    timestamp_end,
    query,
    response,
    total_latency_ms,
    graph_latency_ms,
    time_to_first_token_ms,
    evaluation_latency_ms,
    graph_total_prompt_tokens,
    graph_total_completion_tokens,
    eval_total_prompt_tokens,
    eval_total_completion_tokens
FROM
    {{ source('staging_eval_results_raw', 'daily_load') }}

{% if is_incremental() %}
-- This clause ensures we only process new data on subsequent runs
WHERE timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %}