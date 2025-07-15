-- back compat for old kwarg name
  
  
        
            
                
                
            
                
                
            
                
                
            
                
                
            
        
    

    

    merge into `subtle-poet-311614`.`analytics`.`node_evals` as DBT_INTERNAL_DEST
        using (-- models/node_evals.sql
-- This model unnests the evaluations array to create one row per node evaluation.



SELECT
    t.run_id,
    t.thread_id,
    t.turn_index,
    t.timestamp_start,
    t.graph_version,
    eval.* EXCEPT (explanation)
FROM
    `subtle-poet-311614`.`staging_eval_results_raw`.`daily_load` AS t,
    UNNEST(t.evaluations) AS eval


WHERE t.timestamp_start > (SELECT MAX(timestamp_start) FROM `subtle-poet-311614`.`analytics`.`node_evals`)

        ) as DBT_INTERNAL_SOURCE
        on (
                    DBT_INTERNAL_SOURCE.run_id = DBT_INTERNAL_DEST.run_id
                ) and (
                    DBT_INTERNAL_SOURCE.thread_id = DBT_INTERNAL_DEST.thread_id
                ) and (
                    DBT_INTERNAL_SOURCE.turn_index = DBT_INTERNAL_DEST.turn_index
                ) and (
                    DBT_INTERNAL_SOURCE.node_name = DBT_INTERNAL_DEST.node_name
                )

    
    when matched then update set
        `run_id` = DBT_INTERNAL_SOURCE.`run_id`,`thread_id` = DBT_INTERNAL_SOURCE.`thread_id`,`turn_index` = DBT_INTERNAL_SOURCE.`turn_index`,`timestamp_start` = DBT_INTERNAL_SOURCE.`timestamp_start`,`graph_version` = DBT_INTERNAL_SOURCE.`graph_version`,`handles_irrelevance` = DBT_INTERNAL_SOURCE.`handles_irrelevance`,`answer_relevance` = DBT_INTERNAL_SOURCE.`answer_relevance`,`follows_rules` = DBT_INTERNAL_SOURCE.`follows_rules`,`prompt_tokens` = DBT_INTERNAL_SOURCE.`prompt_tokens`,`persona_adherence` = DBT_INTERNAL_SOURCE.`persona_adherence`,`format_valid` = DBT_INTERNAL_SOURCE.`format_valid`,`classification` = DBT_INTERNAL_SOURCE.`classification`,`completion_tokens` = DBT_INTERNAL_SOURCE.`completion_tokens`,`node_name` = DBT_INTERNAL_SOURCE.`node_name`,`faithfulness` = DBT_INTERNAL_SOURCE.`faithfulness`,`evaluator_name` = DBT_INTERNAL_SOURCE.`evaluator_name`,`timestamp` = DBT_INTERNAL_SOURCE.`timestamp`,`context_relevance` = DBT_INTERNAL_SOURCE.`context_relevance`,`overall_success` = DBT_INTERNAL_SOURCE.`overall_success`
    

    when not matched then insert
        (`run_id`, `thread_id`, `turn_index`, `timestamp_start`, `graph_version`, `handles_irrelevance`, `answer_relevance`, `follows_rules`, `prompt_tokens`, `persona_adherence`, `format_valid`, `classification`, `completion_tokens`, `node_name`, `faithfulness`, `evaluator_name`, `timestamp`, `context_relevance`, `overall_success`)
    values
        (`run_id`, `thread_id`, `turn_index`, `timestamp_start`, `graph_version`, `handles_irrelevance`, `answer_relevance`, `follows_rules`, `prompt_tokens`, `persona_adherence`, `format_valid`, `classification`, `completion_tokens`, `node_name`, `faithfulness`, `evaluator_name`, `timestamp`, `context_relevance`, `overall_success`)


    