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
    doc.content as doc_content,
    CAST(doc.score AS FLOAT64) as doc_score,
    doc.metadata as doc_metadata
FROM
    {{ source('staging_eval_results_raw', 'daily_load') }} AS t,
    UNNEST(
        CASE 
            WHEN t.retrieved_docs IS NULL THEN []
            WHEN JSON_TYPE(t.retrieved_docs) = 'array' THEN t.retrieved_docs
            ELSE []
        END
    ) AS doc

{% if is_incremental() %}
WHERE t.timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %} 