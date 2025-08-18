-- models/retrieved_docs.sql
-- This model unnests the retrieved_docs array to create one row per document.

{{ config(
    materialized='incremental',
    partition_by={
      "field": "timestamp_start",
      "data_type": "timestamp",
      "granularity": "day"
    },
    unique_key=['run_id', 'thread_id', 'turn_index']
) }}

SELECT
    t.run_id,
    t.thread_id,
    t.turn_index,
    t.graph_version,
    t.timestamp_start,
    JSON_VALUE(doc_json, '$.content') as doc_content,
    CAST(JSON_VALUE(doc_json, '$.score') AS FLOAT64) as doc_score,
    JSON_VALUE(doc_json, '$.metadata') as doc_metadata
FROM
    {{ source('staging_eval_results_raw', 'daily_load') }} AS t,
    UNNEST(t.retrieved_docs) AS doc_json
WHERE t.retrieved_docs IS NOT NULL 
  AND ARRAY_LENGTH(t.retrieved_docs) > 0

{% if is_incremental() %}
  AND t.timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %}