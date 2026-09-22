"""A tiny DAG so the UI is not empty. Drop your own files in this folder."""
from datetime import datetime
from airflow.sdk import DAG, task

with DAG("infrapack_hello", start_date=datetime(2024, 1, 1), schedule=None, catchup=False) as dag:
    @task
    def hello():
        print("hello from InfraPack")

    hello()
