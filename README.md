# ChatRaghu dbt Project

**Version: 1.2** | **Last Updated: 2025-01-15**

A comprehensive dbt project for transforming and analyzing LLM evaluation data from an automated GCS to BigQuery ELT pipeline. This project processes conversation turns, retrieved documents, and node evaluations to provide insights into LLM performance and capability assessment.

## 🏗️ System Architecture

This project is part of an automated ELT (Extract, Load, Transform) pipeline that processes LLM evaluation data:

```
GCS (JSONL files) → BigQuery Staging → dbt Transformations → Analytics Tables → Hex Visualization
```

### Pipeline Components

1. **Extract & Load (EL)**: Cloud Function loads JSONL files from GCS into BigQuery staging table
2. **Transform (T)**: dbt models transform raw data into production-ready analytics tables
3. **Visualization**: Hex dashboards provide real-time insights into LLM performance

### Infrastructure

- **Cloud Storage**: `eval_results/` (raw) and `processed_eval_results/` (archive)
- **BigQuery**: Staging table `daily_load` in `staging_eval_results_raw` dataset
- **dbt**: Transformations run via Cloud Run Job with Docker containerization
- **Scheduling**: Cloud Scheduler triggers pipeline every 6 hours

## 📊 Data Models

### Source Table

**`staging_eval_results_raw.daily_load`**
- Raw JSONL data loaded from GCS with auto-detected schema
- Contains conversation turns with nested arrays for retrieved documents and evaluations
- 3-day table expiration for cost optimization

### Production Tables

All tables are materialized as incremental models with daily partitioning on `timestamp_start`.

#### 1. `conversation_turns` (Main Fact Table)
**Purpose**: One row per conversation turn with core metrics and performance data.

**Key Fields**:
- `run_id`, `thread_id`, `turn_index` (unique key)
- `graph_version` - Version of the graph being evaluated
- `timestamp_start`, `timestamp_end` - Timing information
- `query`, `response` - User input and LLM output
- `total_latency_ms`, `graph_latency_ms`, `evaluation_latency_ms` - Performance metrics
- `time_to_first_token_ms` - Response speed indicator
- Token usage for both graph and evaluation phases

#### 2. `retrieved_docs` (Document Retrieval Analysis)
**Purpose**: One row per retrieved document, enabling analysis of retrieval quality.

**Key Fields**:
- `run_id`, `thread_id`, `turn_index` (unique key)
- `doc_content` - Retrieved document text
- `doc_score` - Relevance score from retrieval system
- `doc_metadata` - Additional document metadata

#### 3. `node_evals` (LLM Evaluation Metrics)
**Purpose**: One row per node evaluation, tracking LLM performance across multiple dimensions.

**Key Fields**:
- `run_id`, `thread_id`, `turn_index`, `node_name` (unique key)
- `evaluator_name` - Name of the evaluation component
- `overall_success` - Binary success indicator
- `classification` - Categorization of the response
- **Capability Metrics**:
  - `persona_adherence` - Adherence to specified persona
  - `follows_rules` - Compliance with system rules
  - `format_valid` - Output format correctness
  - `faithfulness` - Accuracy to source material
  - `answer_relevance` - Relevance to user query
  - `handles_irrelevance` - Ability to handle irrelevant inputs
  - `context_relevance` - Context appropriateness
  - `includes_key_info` - Inclusion of essential information

## 🎯 LLM Evaluation Framework

### Capability Funnel Design

The evaluation system implements a multi-layered capability assessment funnel:

1. **Base Functionality** (`overall_success`)
   - Binary pass/fail at the node level
   - Fundamental capability validation

2. **Behavioral Compliance** 
   - `persona_adherence` - Character consistency
   - `follows_rules` - System rule compliance
   - `format_valid` - Output structure validation

3. **Content Quality**
   - `faithfulness` - Source material accuracy
   - `answer_relevance` - Query response relevance
   - `context_relevance` - Situational appropriateness

4. **Advanced Capabilities**
   - `handles_irrelevance` - Noise filtering ability
   - `includes_key_info` - Essential information retention

### Metrics Tracked

- **Performance Metrics**: Latency, token usage, response times
- **Quality Metrics**: Success rates, adherence scores, relevance measures
- **Operational Metrics**: Graph versions, evaluation timestamps, classification data

## 📈 Visualization in Hex

The transformed data is visualized in [Hex dashboards](https://app.hex.tech/019794be-cfa2-700a-986e-d228edf3c6bf/app/Evaluating-AI-at-raghufyi-030GQtNRWQfVqmkZFcpXFp/latest) to provide:

- **Real-time Performance Monitoring**: Latency trends, success rates, token usage
- **Capability Assessment**: Funnel analysis showing where LLM capabilities succeed/fail
- **Document Retrieval Analysis**: Quality of retrieved context and relevance scores
- **Version Comparison**: Performance across different graph versions
- **Operational Insights**: System health, evaluation coverage, data quality metrics

## 📁 Project Structure

```
chatraghu_dbt/
├── models/
│   ├── conversation_turns.sql      # Main fact table
│   ├── retrieved_docs.sql          # Document retrieval analysis
│   ├── node_evals.sql             # LLM evaluation metrics
│   └── sources.yml                # Source table definitions
├── Dockerfile                     # Production container
├── docker-compose.yml             # Local development
├── dbt_project.yml               # Project configuration
├── .dockerignore                 # Docker build exclusions
```


### Incremental Processing

All models use incremental materialization with:
- Daily partitioning on `timestamp_start`
- Unique keys for deduplication
- Schema change handling (`append_new_columns`)


---

**Note**: This project is designed to fit within GCP's free tier for low-to-moderate usage, ensuring cost-effective operation while maintaining production-grade reliability.
