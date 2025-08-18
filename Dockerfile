# Use the official dbt-bigquery image
FROM ghcr.io/dbt-labs/dbt-bigquery:1.8.0

# Set the working directory inside the container
WORKDIR /usr/app/dbt

# Copy your dbt project files into the container
COPY . .

# Create the profiles.yml for production directly in the image
RUN mkdir -p /root/.dbt && \
    echo "chatraghu_dbt:\n  target: prod\n  outputs:\n    prod:\n      type: bigquery\n      method: oauth\n      project: subtle-poet-311614\n      dataset: analytics\n      threads: 4\n      location: us-east1\n      priority: interactive" > /root/.dbt/profiles.yml
