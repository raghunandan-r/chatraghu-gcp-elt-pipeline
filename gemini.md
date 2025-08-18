# Automated GCS to BigQuery ELT Pipeline

**Version: 1.2**
**Last Updated: 2025-07-15**

This document outlines the architecture and implementation details for an automated pipeline that loads JSONL data from Google Cloud Storage (GCS) into a BigQuery staging table and subsequently transforms it into production-ready tables using dbt.

---

## Change Log

* **v1.2 (2025-07-15):**
    * Updated Step 2 (Transform) architecture to reflect a simpler `Cloud Scheduler -> Cloud Run Job` direct invocation.
    * Removed the now-obsolete plan involving a Pub/Sub topic and Eventarc for the dbt transformation trigger.
    * Added a new "Key Learning" section comparing the pros and cons of event-driven vs. direct scheduling for this pipeline.
* **v1.1 (2025-07-14):**
    * Updated GCS folder paths to `eval_results/` (raw) and `processed_eval_results/` (archive).
    * Updated BigQuery staging table name to `daily_load`.
    * Updated Cloud Scheduler frequency to run every 6 hours (`0 */6 * * *`).
    * Updated all corresponding code snippets and configuration files to reflect these changes.
* **v1.0 (Initial Plan):**
    * Initial architecture design.

---

## Phase 1: One-Time Setup

These are the foundational steps that have been completed to prepare the cloud and local environments.

| Task                | Environment   | Service         | Details                                                                                                                                      |
| :------------------ | :------------ | :-------------- | :------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. **Prep GCS Folders** | GCP Console   | **Cloud Storage** | Folders created: `eval_results/` (for new files) and `processed_eval_results/` (for archived files).                                     |
| 2. **Create Staging Table** | BigQuery Studio | **BigQuery** | Manually created the `daily_load` table in the `staging_eval_results_raw` dataset. Schema is auto-detected on load, and a 3-day table expiration is set. |
| 3. **Init dbt Project** | Local Machine | **dbt Core CLI** | A local dbt project has been initialized to manage all SQL transformations.                                                              |

---

## 1. Local Development Environment

-   **`profiles.yml` Location:** Your local `profiles.yml` file (typically `~/.dbt/profiles.yml`) should be configured to point to a **development-specific BigQuery dataset**.
    -   **Example:**
        ```yaml
        chatraghu_dbt:
          target: dev
          outputs:
            dev:
              type: bigquery
              method: oauth
              project: your-gcp-project-id
              dataset: dbt_your_username_dev # <--- CRITICAL: Use a dedicated dev dataset
              threads: 4
        ```
-   **Purpose:** This ensures that any `dbt run` or `dbt test` commands executed from your local machine (or via `docker-compose exec dbt ...`) only affect your development environment, preventing accidental modifications to production data.
-   **Git Ignore:** The local `profiles.yml` **must** be ignored by Git (add `profiles.yml` to your `.gitignore`) to prevent it from being committed to the repository.

## 2. Docker Image for Production Deployment

-   **Purpose:** The dbt models are packaged into a Docker image, which is then pushed to Google Artifact Registry. This image is used by the Cloud Run job for production transformations.
-   **`Dockerfile` Configuration:**
    -   The `Dockerfile` should copy the dbt project code into the image.
    -   **Crucially, the `profiles.yml` for production must be embedded directly into the Docker image.** This makes the image self-contained and independent of external configuration files or environment variables for basic profile setup.
    -   **Example `Dockerfile` Snippet:**
        ```dockerfile
        # Use the official dbt-bigquery image
        FROM ghcr.io/dbt-labs/dbt-bigquery:1.8.0

        # Set the working directory inside the container
        WORKDIR /usr/app/dbt

        # Copy your dbt project files into the container
        # NOTE: .dockerignore prevents local profiles.yml from being copied
        COPY . .

        # Create the profiles.yml for production directly in the image
        # This ensures the production environment always has the correct profile
        RUN mkdir -p /root/.dbt && \
            echo "chatraghu_dbt:\n  target: prod\n  outputs:\n    prod:\n      type: bigquery\n      method: oauth\n      project: subtle-poet-311614\n      dataset: analytics\n      threads: 4\n      location: us-east1\n      priority: interactive" > /root/.dbt/profiles.yml
        ```
-   **`.dockerignore`:** A `.dockerignore` file **must** be present in the root of your project. This file specifies which local files and directories should *not* be copied into the Docker image during the build process.
    -   **Example `.dockerignore` Content:**
        ```
        # Ignore files not needed in the final image
        .dockerignore
        .git/
        .gitignore
        .idea/
        logs/
        target/
        dbt_packages/
        # Crucially, ignore the local profiles file
        profiles.yml
        ```
-   **Building and Pushing:**
    -   Authenticate Docker with Google Artifact Registry:
        `gcloud auth configure-docker us-east1-docker.pkg.dev`
    -   Build and push the Docker image:
        `docker build -t us-east1-docker.pkg.dev/subtle-poet-311614/dbt-repo/dbt-runner:latest . && docker push us-east1-docker.pkg.dev/subtle-poet-311614/dbt-repo/dbt-runner:latest`

## 3. GCP Cloud Run Job (`dbt-transform`) will be referenced later.

-   **Purpose:** The `dbt-transform` Cloud Run job is scheduled to execute the dbt transformations in the production environment.
-   **Image Source:** The job pulls the Docker image from Google Artifact Registry (e.g., `us-east1-docker.pkg.dev/subtle-poet-311614/dbt-repo/dbt-runner:latest`).
-   **Container Command and Arguments:**
    -   **Container command:** `dbt` (This is the entrypoint for the dbt CLI within the container).
    -   **Container arguments:** `run --target prod` (This tells dbt to execute the `run` command and explicitly use the `prod` target defined in the embedded `profiles.yml`).
-   **One-Time Full Refresh (for schema changes):**
    -   When a schema change (like a data type correction) requires a full table rebuild in production, the arguments must be temporarily updated for a single run:
        `run --select your_model_name --full-refresh --target prod`
    -   **CRITICAL:** After the successful full refresh, revert the arguments back to `run --target prod` to resume incremental processing.

This structured approach ensures a clear separation between development and production environments, and a robust deployment pipeline for your dbt projects.


## Phase 2: The Automated ELT Workflow

This two-step, serverless process runs automatically to load and transform data.

### Step 1: Load Raw Data into Staging (The "EL" part)

A serverless function loads new files from GCS into the BigQuery staging table.

* **Environment:** Google Cloud Platform (GCP)
* **Services:** Cloud Scheduler, Pub/Sub, Cloud Functions
* **Implementation Details:**
    1.  A **Cloud Scheduler** job named `run-dbt-load-job` runs every 6 hours (`0 */6 * * *`).
    2.  It sends a message to the **Pub/Sub** topic `run-dbt-load-job`.
    3.  This message triggers the **Cloud Function** `gcs-to-bigquery-staging-loader`.
    4.  The function scans `eval_results/`, loads all `.jsonl` files into the `daily_load` staging table (clearing it first), and moves the processed files to `processed_eval_results/`.

### Step 2: Transform Staging Data into Production Tables (The "T" part)

A scheduled dbt job transforms the raw staging data into final, clean production tables.

* **Environment:** Google Cloud Platform (GCP)
* **Services:** Cloud Scheduler + Cloud Run
* **How it Works:**
    1.  A second **Cloud Scheduler** job (`direct-trigger-dbt-transform`), created via the Cloud Run UI, runs shortly after the load job (`15 */6 * * *`).
    2.  It directly invokes a **Cloud Run Job** which pulls a Docker container with the dbt project.
    3.  The job executes `dbt run`, connecting to BigQuery, reading from the `daily_load` staging table, and building the production tables (`conversation_turns`, `retrieved_docs`, `node_evals`).

---

## Key Learning: Direct Scheduling vs. Event-Driven Triggers

The initial plan for Step 2 was to use a standard event-driven pattern (`Scheduler -> Pub/Sub -> Eventarc -> Cloud Run Job`). However, implementation revealed that the Cloud Run UI provides a simpler, more direct scheduling method. This led to a change in the final architecture.

Below is a critical comparison of the two approaches.

| Pattern                 | Description                                                                                                                           | Pros                                                                                                                                 | Cons                                                                                                                     |
| :---------------------- | :------------------------------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------- |
| **Event-Driven (Pub/Sub)** | The scheduler publishes a message to a Pub/Sub topic. An Eventarc trigger listens to the topic and invokes the Cloud Run Job.       | **Flexible & Decoupled:** Components are independent. Multiple services could react to the same trigger. Good for complex, expanding systems. | **More Complex:** Requires more services (Pub/Sub, Eventarc) and configuration for a simple task.                          |
| **Direct Schedule** | A Cloud Scheduler job is configured to directly invoke the Cloud Run Job, typically via the Cloud Run UI.                               | **Simple & Direct:** Fewer services and easier setup. The link between schedule and action is explicit and easy to trace.      | **Tightly Coupled:** The scheduler is tied to a single job. Less flexible if other services need to run on the same trigger in the future. |

**Conclusion:** For this linear pipeline where one scheduled event triggers one specific action, the **Direct Schedule** approach was the most pragmatic and efficient choice. It reduced complexity without sacrificing necessary functionality.

---

## dbt Project Deep Dive

This section details the internal workings of the dbt project, including the data flow, transformation logic, and how it handles dynamic schemas.

### Data Flow: From Source to Production

The entire transformation process is governed by dbt and the configuration files in this project.

1.  **Source Data:**
    * **Source Table:** `subtle-poet-311614.staging_eval_results_raw.daily_load`
    * **Configuration:** Defined in `models/sources.yml`.
    * **Description:** This is the raw, unprocessed JSONL data loaded directly from GCS. Its schema is flexible and determined by BigQuery's auto-detection.

2.  **Destination (Production) Data:**
    * **Destination Dataset:** `subtle-poet-311614.analytics`
    * **Configuration:** Defined in `profiles.yml` under the `dev` target's `dataset` key.
    * **Description:** This dataset holds the clean, structured, and production-ready tables. If this dataset does not exist when `dbt run` is executed, dbt will automatically create it.

### The dbt Transformation Logic

dbt works by transforming data declaratively. You write a `SELECT` statement describing the final table you want, and dbt handles the `CREATE TABLE`, `INSERT`, or `MERGE` operations automatically.

* **Execution Order:** dbt builds a Directed Acyclic Graph (DAG) of dependencies. In this project, all three models depend only on the `daily_load` source table. Therefore, dbt runs all three transformations in parallel for maximum efficiency.

* **Destination Tables:** The transformed data is split into three granular, production-ready tables in the `analytics` dataset:
    1.  `analytics.conversation_turns`
    2.  `analytics.retrieved_docs`
    3.  `analytics.node_evals`

### Handling Dynamic Schemas

The pipeline is designed to be robust to changes in the source data, particularly within the nested `evaluations` data.

1.  **Automated Type Inference:** When BigQuery loads a new JSONL file, it uses `autodetect=True` to automatically infer the data types (e.g., `BOOLEAN`, `INTEGER`, `STRING`) for any new fields it encounters. This schema is passed to the `daily_load` staging table.

2.  **Dynamic Column Expansion in dbt:** The `models/node_evals.sql` model uses the `eval.* EXCEPT (explanation)` syntax. This is a powerful, low-maintenance approach:
    * `eval.*`: This automatically includes every field from the unnested `evaluations` struct as a column.
    * `EXCEPT (explanation)`: This explicitly excludes the `explanation` field, which may be too large or noisy for analytics.
    * **Benefit:** When a new evaluation metric (e.g., `faithfulness`, `persona_adherence`) is added to the source JSONL files, this model will automatically add it as a new column to the `analytics.node_evals` table on the next `dbt run`. No manual code changes are required.

### `unique_key` in dbt Models

The `unique_key` configuration in dbt models is crucial for incremental loads and ensuring data uniqueness. It's important that the columns specified in `unique_key` accurately represent a unique combination of values for each row in the final transformed table. These keys must match the final column names in your `SELECT` statement.

---

## Implementation Details & Code

This section contains the specific configurations and scripts used in the project.

### Cloud Function: `gcs-to-bigquery-staging-loader`

**`main.py`**

```python
import os
import functions_framework
from google.cloud import bigquery, storage

@functions_framework.cloud_event
def load_gcs_to_staging(cloud_event):
    """
    Cloud Function to load all .jsonl files from a GCS folder into a BigQuery staging table,
    then move the processed files to an archive folder.
    Triggered by a message on a Cloud Pub/Sub topic.
    """
    # --- Configuration ---
    project_id = os.environ.get('GCP_PROJECT')
    bucket_name = os.environ.get('GCS_BUCKET_NAME')
    dataset_id = 'staging_eval_results_raw'
    staging_table_name = 'daily_load'

    raw_folder = 'eval_results/'
    processed_folder = 'processed_eval_results/'

    # --- Initialize Clients ---
    storage_client = storage.Client()
    bq_client = bigquery.Client()
    bucket = storage_client.bucket(bucket_name)

    # --- Construct BigQuery Table ID ---
    staging_table_id = f"{project_id}.{dataset_id}.{staging_table_name}"

    # 1. Get a list of files to process
    blobs_to_process = list(bucket.list_blobs(prefix=raw_folder))
    source_uris = [f"gs://{bucket_name}/{blob.name}" for blob in blobs_to_process if blob.name.endswith('.jsonl')]

    if not source_uris:
        print("No new .jsonl files to process.")
        return "No new files to process.", 200

    # 2. Define the BigQuery Load Job Configuration
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        autodetect=True,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )

    # 3. Load all files into the staging table
    print(f"Loading {len(source_uris)} files into {staging_table_id}...")
    load_job = bq_client.load_table_from_uri(source_uris, staging_table_id, job_config=job_config)

    try:
        load_job.result()
        print("Load job completed successfully.")
    except Exception as e:
        print(f"Load job failed: {e}")
        return "Load job failed.", 500

    # 4. Move processed files to the archive folder
    print(f"Moving {len(source_uris)} files to archive...")
    for blob in blobs_to_process:
        if blob.name.endswith('.jsonl'):
            destination_blob_name = blob.name.replace(raw_folder, processed_folder, 1)
            bucket.copy_blob(blob, bucket, destination_blob_name)
            blob.delete()

    print("Process complete.")
    return "Process complete.", 200
```

---

## Phase 3: Your dbt Development Workflow

This is how you will write and manage your transformations. This context is provided to enable development with Gemini CLI in the current project.

* **Environment:** Your Local Machine
* **Services:** Your Code Editor (e.g., VS Code) + dbt Core CLI + Git
* **How it Works:**
    1.  You write and edit the transformation logic in the `.sql` model files on your computer.
    2.  You test your changes by running `dbt run` or `dbt build` from your terminal, which updates your development dataset in BigQuery.
    3.  Once you're happy, you commit your changes to a Git repository (like GitHub). The Cloud Run Job in the automated workflow is configured to pull the latest code from this repository, ensuring your production runs are always up-to-date.

---

## Free Tier & Cost-Effectiveness ✅

This entire architecture is designed to fit comfortably within GCP's free tier for low-to-moderate usage.

* **Cloud Storage:** The first 5 GB-month of storage is free.
* **BigQuery:** 10 GB of storage and 1 TB of queries per month are free.
* **Cloud Functions:** The first 2 million invocations per month are free.
* **Cloud Scheduler:** The first 3 jobs per account are free. You only need two.
* **Cloud Run:** A generous amount of free vCPU-seconds and memory is included, which is more than enough for a daily dbt job.

This serverless approach ensures you're not paying for idle virtual machines and are only using resources exactly when needed, which is the definition of maintaining best practices without over-engineering.

## Phase 2 In Detail 
### How to Set Up dbt Locally with Docker
Using Docker is the best way to ensure your local development environment matches the production environment on Cloud Run.

* Create Project Structure: Inside your dbt project folder, create the following two files.

```bash
    # Dockerfile
    # This file defines the container for your dbt project.

    # Use the official dbt-bigquery image
    FROM ghcr.io/dbt-labs/dbt-bigquery:1.8.0

    # Set the working directory inside the container
    WORKDIR /usr/app/dbt

    # Copy your dbt project files into the container
    COPY . .

    # This tells dbt where to find the profiles.yml file inside the container
    ENV DBT_PROFILES_DIR=.
    ```yaml
    # docker-compose.yml
    # This file makes it easy to run your dbt container locally.

    version: '3.8'
    services:
    dbt:
        build:
        context: .
        dockerfile: Dockerfile
        volumes:
        # This mounts your local dbt project files into the container,
        # so changes you make locally are reflected instantly.
        - .:/usr/app/dbt
        # This mounts your local GCP credentials into the container
        - ~/.config/gcloud:/root/.config/gcloud
        # This keeps the container running so you can execute commands in it
        command: tail -f /dev/null

```
* Build and Run: From your terminal in the dbt project directory, run docker-compose up -d. This will build the container and run it in the background.
* Execute dbt Commands: You can now run any dbt command inside the container. For example: docker-compose exec -T dbt dbt run.


### How to Establish the BigQuery Connection
dbt connects to BigQuery using a profiles.yml file. This file contains your credentials and project details.

**DataGrip Connection:** For DataGrip, connect to BigQuery using a service account key file and set the `OAuthServiceAcctEmail` property.

Authenticate Locally: First, run gcloud auth application-default login in your local terminal. This command will open a browser window for you to log in to your Google account and will store your credentials locally. The docker-compose.yml file is configured to mount these credentials into the container.

Create profiles.yml: In your dbt project folder, create the profiles.yml file.

```yaml
# profiles.yml

your_project_name: # This should match the name in your dbt_project.yml
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: subtle-poet-311614 # e.g., subtle-poet-311614
      dataset: analytics # This is the dataset where dbt will build your production tables
      threads: 4 # Number of concurrent models to run
      location: us-east1 # The location of your BigQuery dataset
      priority: interactive
```

### SQL Queries to Run in dbt
These are the three models that will perform your transformations. Place them in the models/ directory of your dbt project.

```sql
-- models/conversation_turns.sql
-- This model creates the main fact table with one row per conversation turn.

{{ config(
    materialized='incremental',
    partition_by = {
      "field": "timestamp_start",
      "data_type": "timestamp",
      "granularity": "day"
    },
    unique_key=['run_id', 'thread_id', 'turn_index']
) }}

SELECT
    run_id,
    thread_id,
    turn_index,
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
    {{ source('staging_eval_results_raw', 'daily_load') }}

{% if is_incremental() %}
-- This clause ensures we only process new data on subsequent runs
WHERE timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %}
```

```sql
-- models/retrieved_docs.sql
-- This model unnests the retrieved_docs array to create one row per document.

{{ config(
    materialized='incremental',
    partition_by = {
      "field": "timestamp_start",
      "data_type": "timestamp",
      "granularity": "day"
    },
    unique_key=['run_id', 'thread_id', 'turn_index', 'doc_content'] -- Added content to key for uniqueness
) }}

SELECT
    t.run_id,
    t.thread_id,
    t.turn_index,
    t.timestamp_start,
    doc.content as doc_content,
    doc.score as doc_score,
    doc.metadata as doc_metadata
FROM
    {{ source('staging_eval_results_raw', 'daily_load') }} AS t,
    UNNEST(t.retrieved_docs) AS doc

{% if is_incremental() %}
WHERE t.timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %}
```


```sql
-- models/node_evals.sql
-- This model unnests the evaluations array to create one row per node evaluation.

{{ config(
    materialized='incremental',
    partition_by = {
      "field": "timestamp_start",
      "data_type": "timestamp",
      "granularity": "day"
    },
    unique_key=['run_id', 'thread_id', 'turn_index', 'node_name'] -- Added node_name for uniqueness
) }}

SELECT
    t.run_id,
    t.thread_id,
    t.turn_index,
    t.timestamp_start,
    eval.node_name,
    eval.evaluator_name,
    eval.overall_success,
    eval.explanation,
    eval.prompt_tokens,
    eval.completion_tokens
FROM
    {{ source('staging_eval_results_raw', 'daily_load') }} AS t,
    UNNEST(t.evaluations) AS eval

{% if is_incremental() %}
WHERE t.timestamp_start > (SELECT MAX(timestamp_start) FROM {{ this }})
{% endif %}

```

# GCP ELT Pipeline: Architecture & Setup Guide

This document outlines the architecture for the automated ELT pipeline and the key configuration steps required in Google Cloud Platform. It includes learnings from setting up Step 1 to ensure a smooth setup for Step 2.

## Architecture Overview

The pipeline follows a serverless, event-driven architecture:

`Cloud Scheduler` ➡️ `Pub/Sub Topic` ➡️ `Cloud Run Service`

- **Step 1 (Extract-Load):** A Cloud Run service (`gcs-to-bigquery-staging-loader`) handles the EL part.
- **Step 2 (Transform):** A second Cloud Run service will be created to handle the T part by running `dbt`.

---

## Key Learnings & Configuration Rules

The primary challenge in setup is correctly configuring the permissions between a **Pub/Sub push subscription** and a secure **Cloud Run service**.

### 1. The Core Authentication Principle
Secure Cloud Run services (the default) require that any service trying to trigger them, like Pub/Sub, must prove its identity. By default, a Pub/Sub push subscription sends an unauthenticated request, which Cloud Run will reject.

### 2. Use a Dedicated Service Account
Do not use the broad-permission 'Default Compute Service Account'. To follow the principle of least privilege:
- **Action:** Create a single, dedicated service account for triggering the pipeline steps.
- **Example Name:** `pubsub-cloud-run-invoker@subtle-poet-311614.iam.gserviceaccount.com`

### 3. Use the `Cloud Run Invoker` Role
The correct permission to allow a service account to trigger a Cloud Run service is **`Cloud Run Invoker`**.
- **Action:** This role must be granted on the **Cloud Run service itself**, not at the project level.
- **Location:** `Cloud Run > [Your Service Name] > Security Tab > Grant Access`.

### 4. Configure the Pub/Sub Subscription Correctly
You do not assign a role *to* the Pub/Sub subscription. You **edit the subscription's settings** to tell it to *use* the service account's identity.
- **Action:** Edit the subscription and navigate to the **Push configuration** section.
- **Location:** `Pub/Sub > Subscriptions > [Your Subscription ID] > Edit > Authentication > Service account`.

---

## Action Plan for Step 2 (dbt Transform)

To set up the dbt transformation job, apply the learnings above:

1.  **Deploy the dbt Cloud Run Service:**
    - Create and deploy your new Cloud Run service that is containerized to run your dbt jobs.

2.  **Grant Invoker Permission:**
    - Navigate to the **Security** tab of this **new dbt service**.
    - Grant the `Cloud Run Invoker` role to your existing `pubsub-cloud-run-invoker@subtle-poet-311614.iam.gserviceaccount.com` service account. You can reuse the same one.

3.  **Create and Configure the dbt Pub/Sub Trigger:**
    - Create a new Pub/Sub topic (e.g., `run-dbt-transform-job`).
    - Create a new push subscription for that topic, pointing to the URL of your new dbt Cloud Run service.
    - **Edit this new subscription** and configure its **Authentication** setting to use the `pubsub-cloud-run-invoker@subtle-poet-311614.iam.gserviceaccount.com` service account.

4.  **Create the Final Cloud Scheduler Job:**
    - Create a new Cloud Scheduler job to publish a message to the `run-dbt-transform-job` topic, likely scheduled to run after Step 1 is expected to be complete.

---
## Gemini CLI Context
> When working on Step 2 of the ELT pipeline, assume the architecture and security principles outlined in this document are the intended plan. The key components are a dedicated service account (`pubsub-cloud-run-invoker@subtle-poet-311614.iam.gserviceaccount.com`) acting as the identity for Pub/Sub push subscriptions, and the `Cloud Run Invoker` role being granted on each Cloud Run service.

