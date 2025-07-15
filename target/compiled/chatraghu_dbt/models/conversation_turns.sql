-- models/conversation_turns.sql
-- This model creates the main fact table with one row per conversation turn.



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
    evaluation_latency_ms,
    graph_total_prompt_tokens,
    graph_total_completion_tokens,
    eval_total_prompt_tokens,
    eval_total_completion_tokens
FROM
    `subtle-poet-311614`.`staging_eval_results_raw`.`daily_load`


-- This clause ensures we only process new data on subsequent runs
WHERE timestamp_start > (SELECT MAX(timestamp_start) FROM `subtle-poet-311614`.`analytics`.`conversation_turns`)
