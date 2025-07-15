-- models/node_evals.sql
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
