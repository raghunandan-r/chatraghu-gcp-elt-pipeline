-- dbt model structure: marts/conversation_performance_daily.sql
-- models/conversation_performance_daily.sql
-- This model calculates the performance metrics for each conversation.

{{ config(
  materialized='incremental',
  incremental_strategy='merge',
  unique_key=['conversation_date','graph_version'],
  partition_by={'field': 'conversation_date', 'data_type': 'date'},
  cluster_by=['graph_version']
) }}

WITH base_turns AS (
  SELECT 
    run_id,
    thread_id,
    turn_index,
    graph_version,
    DATE(timestamp_start) as conversation_date,
    timestamp_start,
    timestamp_end,
    
    -- Latency metrics in milliseconds
    total_latency_ms,
    graph_latency_ms,
    evaluation_latency_ms,
    time_to_first_token_ms,
    
    -- Token usage
    graph_total_prompt_tokens,
    graph_total_completion_tokens,
    eval_total_prompt_tokens,
    eval_total_completion_tokens
    
  FROM {{ ref('conversation_turns') }}
  WHERE (
    {% if is_incremental() %}
      DATE(timestamp_start) >= DATE_SUB((
        SELECT IFNULL(MAX(conversation_date), DATE '1970-01-01') FROM {{ this }}
      ), INTERVAL 3 DAY)
    {% else %}
      TRUE
    {% endif %}
  )
),

latency_conversions AS (
  SELECT *,
    -- Convert to seconds for easier analysis
    total_latency_ms / 1000.0 AS total_latency_s,
    graph_latency_ms / 1000.0 AS graph_latency_s,
    evaluation_latency_ms / 1000.0 AS evaluation_latency_s,
    time_to_first_token_ms / 1000.0 AS time_to_first_token_s

  FROM base_turns
)

SELECT 
  conversation_date,
  graph_version,
  
  -- Count metrics
  COUNT(*) as total_conversations,
  COUNT(DISTINCT thread_id) as unique_threads,
  
  APPROX_QUANTILES(graph_latency_s, 100)[OFFSET(50)] as graph_latency_p50,
  APPROX_QUANTILES(graph_latency_s, 100)[OFFSET(90)] as graph_latency_p90,
  APPROX_QUANTILES(graph_latency_s, 100)[OFFSET(99)] as graph_latency_p99,
  
  APPROX_QUANTILES(time_to_first_token_s, 100)[OFFSET(50)] as ttft_p50,
  APPROX_QUANTILES(time_to_first_token_s, 100)[OFFSET(90)] as ttft_p90,
  APPROX_QUANTILES(time_to_first_token_s, 100)[OFFSET(99)] as ttft_p99,
  
  -- Performance flags
  SUM(CASE WHEN total_latency_s > 30 THEN 1 ELSE 0 END) as slow_responses_count,
  SUM(CASE WHEN time_to_first_token_s > 5 THEN 1 ELSE 0 END) as slow_ttft_count

FROM latency_conversions
GROUP BY conversation_date, graph_version
-- ORDER BY conversation_date DESC, graph_version