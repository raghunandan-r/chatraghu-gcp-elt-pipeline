-- models/retrieved_docs.sql
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
