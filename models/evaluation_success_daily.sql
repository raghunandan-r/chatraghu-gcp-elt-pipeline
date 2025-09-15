-- dbt model structure: marts/evaluation_success_daily.sql
-- models/evaluation_success_daily.sql
-- This model calculates the success rate for each evaluation path.

{{ config(
  materialized='incremental',
  incremental_strategy='merge',
  unique_key=['evaluation_date','graph_version','execution_path','evaluator_name'],
  partition_by={'field': 'evaluation_date', 'data_type': 'date'},
  cluster_by=['graph_version','execution_path']
) }}

WITH evaluation_base AS (
    SELECT
        run_id,
        thread_id,
        turn_index,
        graph_version,
        evaluator_name,
        node_name,
        routing_correct,

        -- Boolean evaluation results
        overall_success,
        faithfulness,
        answer_relevance,
        includes_key_info,
        handles_irrelevance,
        is_clear,
        is_safe,
        document_relevance,
        context_relevance,
        response_appropriateness,
        persona_adherence,
        format_valid,
        follows_rules,
        DATE(timestamp) AS evaluation_date,

        -- Determine execution path
        CASE
            WHEN node_name = 'generate_answer_with_rag' THEN 'RAG Path'
            WHEN
                node_name = 'generate_simple_response'
                THEN 'Simple Response Path'
            WHEN node_name = 'router' THEN 'Router'
            ELSE 'Other'
        END AS execution_path

     FROM {{ ref('node_evals') }}
    WHERE graph_version LIKE 'i1%'
    AND (
      {% if is_incremental() %}
        DATE(timestamp) >= DATE_SUB((
          SELECT IFNULL(MAX(evaluation_date), DATE '1970-01-01') FROM {{ this }}
        ), INTERVAL 1 DAY)
      {% else %}
        TRUE
      {% endif %}
    )
),

-- Calculate success rates by path and evaluator
path_success_rates AS (
    SELECT
        evaluation_date,
        graph_version,
        execution_path,
        evaluator_name,

        COUNT(*) AS total_evaluations,

        -- Router-specific metrics
        SUM(CASE WHEN routing_correct IS TRUE THEN 1 ELSE 0 END)
            AS correct_routing_count,
        AVG(
            CASE
                WHEN
                    routing_correct IS NOT NULL
                    THEN CAST(routing_correct AS INT64)
            END
        ) AS routing_success_rate,

        -- RAG-specific metrics  
        SUM(CASE WHEN faithfulness IS TRUE THEN 1 ELSE 0 END)
            AS faithful_responses,
        AVG(
            CASE
                WHEN faithfulness IS NOT NULL THEN CAST(faithfulness AS INT64)
            END
        ) AS faithfulness_rate,

        SUM(CASE WHEN answer_relevance IS TRUE THEN 1 ELSE 0 END)
            AS relevant_answers,
        AVG(
            CASE
                WHEN
                    answer_relevance IS NOT NULL
                    THEN CAST(answer_relevance AS INT64)
            END
        ) AS answer_relevance_rate,

        SUM(CASE WHEN includes_key_info IS TRUE THEN 1 ELSE 0 END)
            AS includes_key_info_count,
        AVG(
            CASE
                WHEN
                    includes_key_info IS NOT NULL
                    THEN CAST(includes_key_info AS INT64)
            END
        ) AS key_info_inclusion_rate,

        -- General quality metrics
        SUM(CASE WHEN overall_success IS TRUE THEN 1 ELSE 0 END)
            AS overall_success_count,
        AVG(
            CASE
                WHEN
                    overall_success IS NOT NULL
                    THEN CAST(overall_success AS INT64)
            END
        ) AS overall_success_rate,

        SUM(CASE WHEN is_clear IS TRUE THEN 1 ELSE 0 END) AS clear_responses,
        AVG(CASE WHEN is_clear IS NOT NULL THEN CAST(is_clear AS INT64) END)
            AS clarity_rate,

        SUM(CASE WHEN is_safe IS TRUE THEN 1 ELSE 0 END) AS safe_responses,
        AVG(CASE WHEN is_safe IS NOT NULL THEN CAST(is_safe AS INT64) END)
            AS safety_rate

    FROM evaluation_base
    GROUP BY evaluation_date, graph_version, execution_path, evaluator_name
)

SELECT
    evaluation_date,
    graph_version,
    execution_path,
    evaluator_name,
    total_evaluations,

    -- Success rates (as percentages)
    correct_routing_count,
    faithful_responses,
    relevant_answers,
    includes_key_info_count,
    overall_success_count,
    clear_responses,
    safe_responses,

    -- Raw counts for deeper analysis
    ROUND(routing_success_rate * 100, 2) AS routing_success_pct,
    ROUND(faithfulness_rate * 100, 2) AS faithfulness_pct,
    ROUND(answer_relevance_rate * 100, 2) AS answer_relevance_pct,
    ROUND(key_info_inclusion_rate * 100, 2) AS key_info_inclusion_pct,
    ROUND(overall_success_rate * 100, 2) AS overall_success_pct,
    ROUND(clarity_rate * 100, 2) AS clarity_pct,
    ROUND(safety_rate * 100, 2) AS safety_pct

FROM path_success_rates
ORDER BY
    evaluation_date DESC,
    graph_version ASC,
    execution_path ASC,
    evaluator_name ASC
