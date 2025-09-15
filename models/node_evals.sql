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
    t.turn_index + 1 as turn_index,
    t.timestamp_start,
    t.graph_version,
    eval.node_name,
    eval.evaluator_name,
    eval.timestamp,
    eval.overall_success,
    eval.prompt_tokens,
    eval.completion_tokens,
    eval.classification,
    eval.faithfulness, 
    eval.answer_relevance, 
    eval.handles_irrelevance,
    eval.includes_key_info, 
    eval.routing_correct, 
    eval.response_appropriateness, 
    eval.history_relevance, 
    eval.document_relevance,
    eval.is_safe,
    eval.is_clear
FROM
    {{ source('staging_eval_results_raw', 'daily_load') }} AS t,
    UNNEST(t.evaluations) AS eval

{% if is_incremental() %}
WHERE t.timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %}