-- models/costs_per_query.sql
-- This model calculates the cost per query for each individual query.

{{ config(
  materialized='incremental',
  incremental_strategy='merge',
  unique_key=['date','graph_version'],
  partition_by={'field': 'date', 'data_type': 'date'},
  cluster_by=['graph_version']
) }}

WITH costs_per_individual_query AS (
  SELECT 
    run_id, 
    thread_id, 
    turn_index, 
    graph_version, 
    timestamp_start,
    CASE 
      WHEN graph_version = 'i1.0.0' THEN
        ((graph_total_prompt_tokens + eval_total_prompt_tokens) / 1000000) * {{ var('i1_0_0_prompt_price') }} + 
        ((graph_total_completion_tokens + eval_total_completion_tokens) / 1000000) * {{ var('i1_0_0_completion_price') }} 
      WHEN graph_version = 'i1.0.1' THEN
        (graph_total_prompt_tokens / 1000000) * {{ var('i1_0_1_graph_prompt_price') }} + 
        (eval_total_prompt_tokens / 1000000) * {{ var('i1_0_1_eval_prompt_price') }} + 
        (graph_total_completion_tokens / 1000000) * {{ var('i1_0_1_graph_completion_price') }} + 
        (eval_total_completion_tokens / 1000000) * {{ var('i1_0_1_eval_completion_price') }} 
    END AS cost_per_query_total
  FROM {{ ref('conversation_turns') }}
  WHERE (
    {% if is_incremental() %}
      DATE(timestamp_start) >= DATE_SUB((
        SELECT IFNULL(MAX(date), DATE '1970-01-01') FROM {{ this }}
      ), INTERVAL 3 DAY)
    {% else %}
      TRUE
    {% endif %}
  )
)
SELECT 
  DATE(timestamp_start) as date,
  graph_version,
  AVG(cost_per_query_total) as avg_cost_per_query,
  SUM(cost_per_query_total) as total_daily_cost,
  COUNT(*) as query_count
FROM costs_per_individual_query
GROUP BY DATE(timestamp_start), graph_version
-- ORDER BY date, graph_version