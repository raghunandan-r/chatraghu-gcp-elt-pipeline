-- back compat for old kwarg name
  
  
        
            
                
                
            
                
                
            
                
                
            
        
    

    

    merge into `subtle-poet-311614`.`analytics`.`retrieved_docs` as DBT_INTERNAL_DEST
        using (-- models/retrieved_docs.sql
-- This model unnests the retrieved_docs array to create one row per document.



SELECT
    t.run_id,
    t.thread_id,
    t.turn_index,
    t.graph_version,
    t.timestamp_start,
    doc.content as doc_content,
    doc.score as doc_score,
    doc.metadata as doc_metadata
FROM
    `subtle-poet-311614`.`staging_eval_results_raw`.`daily_load` AS t,
    UNNEST(t.retrieved_docs) AS doc


WHERE t.timestamp_start > (SELECT MAX(timestamp_start) FROM `subtle-poet-311614`.`analytics`.`retrieved_docs`)

        ) as DBT_INTERNAL_SOURCE
        on (
                    DBT_INTERNAL_SOURCE.run_id = DBT_INTERNAL_DEST.run_id
                ) and (
                    DBT_INTERNAL_SOURCE.thread_id = DBT_INTERNAL_DEST.thread_id
                ) and (
                    DBT_INTERNAL_SOURCE.turn_index = DBT_INTERNAL_DEST.turn_index
                )

    
    when matched then update set
        `run_id` = DBT_INTERNAL_SOURCE.`run_id`,`thread_id` = DBT_INTERNAL_SOURCE.`thread_id`,`turn_index` = DBT_INTERNAL_SOURCE.`turn_index`,`graph_version` = DBT_INTERNAL_SOURCE.`graph_version`,`timestamp_start` = DBT_INTERNAL_SOURCE.`timestamp_start`,`doc_content` = DBT_INTERNAL_SOURCE.`doc_content`,`doc_score` = DBT_INTERNAL_SOURCE.`doc_score`,`doc_metadata` = DBT_INTERNAL_SOURCE.`doc_metadata`
    

    when not matched then insert
        (`run_id`, `thread_id`, `turn_index`, `graph_version`, `timestamp_start`, `doc_content`, `doc_score`, `doc_metadata`)
    values
        (`run_id`, `thread_id`, `turn_index`, `graph_version`, `timestamp_start`, `doc_content`, `doc_score`, `doc_metadata`)


    