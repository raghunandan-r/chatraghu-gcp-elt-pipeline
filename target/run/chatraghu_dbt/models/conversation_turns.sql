-- back compat for old kwarg name
  
  
        
            
                
                
            
                
                
            
                
                
            
        
    

    

    merge into `subtle-poet-311614`.`analytics`.`conversation_turns` as DBT_INTERNAL_DEST
        using (-- models/conversation_turns.sql
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

        ) as DBT_INTERNAL_SOURCE
        on (
                    DBT_INTERNAL_SOURCE.run_id = DBT_INTERNAL_DEST.run_id
                ) and (
                    DBT_INTERNAL_SOURCE.thread_id = DBT_INTERNAL_DEST.thread_id
                ) and (
                    DBT_INTERNAL_SOURCE.turn_index = DBT_INTERNAL_DEST.turn_index
                )

    
    when matched then update set
        `run_id` = DBT_INTERNAL_SOURCE.`run_id`,`thread_id` = DBT_INTERNAL_SOURCE.`thread_id`,`turn_index` = DBT_INTERNAL_SOURCE.`turn_index`,`graph_version` = DBT_INTERNAL_SOURCE.`graph_version`,`timestamp_start` = DBT_INTERNAL_SOURCE.`timestamp_start`,`timestamp_end` = DBT_INTERNAL_SOURCE.`timestamp_end`,`query` = DBT_INTERNAL_SOURCE.`query`,`response` = DBT_INTERNAL_SOURCE.`response`,`total_latency_ms` = DBT_INTERNAL_SOURCE.`total_latency_ms`,`graph_latency_ms` = DBT_INTERNAL_SOURCE.`graph_latency_ms`,`evaluation_latency_ms` = DBT_INTERNAL_SOURCE.`evaluation_latency_ms`,`graph_total_prompt_tokens` = DBT_INTERNAL_SOURCE.`graph_total_prompt_tokens`,`graph_total_completion_tokens` = DBT_INTERNAL_SOURCE.`graph_total_completion_tokens`,`eval_total_prompt_tokens` = DBT_INTERNAL_SOURCE.`eval_total_prompt_tokens`,`eval_total_completion_tokens` = DBT_INTERNAL_SOURCE.`eval_total_completion_tokens`
    

    when not matched then insert
        (`run_id`, `thread_id`, `turn_index`, `graph_version`, `timestamp_start`, `timestamp_end`, `query`, `response`, `total_latency_ms`, `graph_latency_ms`, `evaluation_latency_ms`, `graph_total_prompt_tokens`, `graph_total_completion_tokens`, `eval_total_prompt_tokens`, `eval_total_completion_tokens`)
    values
        (`run_id`, `thread_id`, `turn_index`, `graph_version`, `timestamp_start`, `timestamp_end`, `query`, `response`, `total_latency_ms`, `graph_latency_ms`, `evaluation_latency_ms`, `graph_total_prompt_tokens`, `graph_total_completion_tokens`, `eval_total_prompt_tokens`, `eval_total_completion_tokens`)


    