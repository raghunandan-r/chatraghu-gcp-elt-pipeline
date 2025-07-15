# Use the official dbt-bigquery image
FROM ghcr.io/dbt-labs/dbt-bigquery:1.8.0

# Set the working directory inside the container
WORKDIR /usr/app/dbt

# Copy your dbt project files into the container
COPY . .

# This tells dbt where to find the profiles.yml file inside the container
ENV DBT_PROFILES_DIR=.