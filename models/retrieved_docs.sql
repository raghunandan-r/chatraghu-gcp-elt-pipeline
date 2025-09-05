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
    doc.score as doc_score,
    doc.metadata.id as doc_metadata_id,
    doc.metadata.section_title as doc_metadata_section_title,
    doc.metadata.parent_section as doc_metadata_parent_section,
    doc.metadata.source as doc_metadata_source,
    doc.metadata.language as doc_metadata_language,
    doc.metadata.original_score as doc_metadata_original_score,
    doc.metadata.rerank_score as doc_metadata_rerank_score,
    doc.metadata.score_by_source as doc_metadata_score_by_source,
    doc.metadata.index_source as doc_metadata_index_source,
    doc.metadata.namespace as doc_metadata_namespace,

FROM
    {{ source('staging_eval_results_raw', 'daily_load') }} AS t,
    UNNEST(t.retrieved_docs) AS doc
WHERE t.retrieved_docs IS NOT NULL 
  AND ARRAY_LENGTH(t.retrieved_docs) > 0

{% if is_incremental() %}
  AND t.timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %}