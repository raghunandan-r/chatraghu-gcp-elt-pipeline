-- models/node_evals.sql
-- This model unnests the evaluations array to create one row per node evaluation.

{{ config(
    materialized='incremental',
    partition_by={
      "field": "timestamp_start",
      "data_type": "timestamp",
      "granularity": "day"
    },
    unique_key=['run_id', 'thread_id', 'turn_index', 'node_name'],
    on_schema_change='append_new_columns'
) }}

SELECT
    t.run_id,
    t.thread_id,
    t.turn_index,
    t.timestamp_start,
    t.graph_version,
    eval.node_name,
    eval.evaluator_name,
    eval.timestamp,
    eval.overall_success,
    eval.prompt_tokens,
    eval.completion_tokens,
    COALESCE(eval.classification, 'unknown') as classification,
    COALESCE(CAST(JSON_VALUE(TO_JSON_STRING(eval), '$.persona_adherence') AS BOOL), FALSE) as persona_adherence, -- ghosts of christmas past.
    COALESCE(CAST(JSON_VALUE(TO_JSON_STRING(eval), '$.follows_rules') AS BOOL), FALSE) as follows_rules,
    COALESCE(CAST(JSON_VALUE(TO_JSON_STRING(eval), '$.format_valid') AS BOOL), FALSE) as format_valid,    
    COALESCE(eval.faithfulness, FALSE) as faithfulness,
    COALESCE(eval.answer_relevance, FALSE) as answer_relevance,
    COALESCE(eval.handles_irrelevance, FALSE) as handles_irrelevance,
    COALESCE(eval.context_relevance, FALSE) as context_relevance,
    COALESCE(eval.includes_key_info, FALSE) as includes_key_info
FROM
    {{ source('staging_eval_results_raw', 'daily_load') }} AS t,
    UNNEST(t.evaluations) AS eval

{% if is_incremental() %}
WHERE t.timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %}