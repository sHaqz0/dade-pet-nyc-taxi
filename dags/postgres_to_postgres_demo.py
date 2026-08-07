from airflow import DAG
from airflow.decorators import task
from airflow.providers.postgres.hooks.postgres import PostgresHook
from datetime import datetime

with DAG(
    dag_id="postgres_to_postgres_demo",
    start_date=datetime(2024, 1, 1),
    schedule=None,       # запускаем только вручную, это тренировочный DAG
    catchup=False,
    tags=["training"],
) as dag:

    @task
    def copy_sample_data():
        source_hook = PostgresHook(postgres_conn_id="postgres_source")
        target_hook = PostgresHook(postgres_conn_id="postgres_target")

        # берём небольшой кусок для тренировки, не всю таблицу целиком
        df = source_hook.get_pandas_df("SELECT * FROM trips_raw LIMIT 100000")

        target_engine = target_hook.get_sqlalchemy_engine()
        df.to_sql(
            "trips_raw_copy",
            target_engine,
            if_exists="replace",
            index=False,
            chunksize=10000,
        )
        print(f"Скопировано {len(df)} строк в taxi_db_replica.trips_raw_copy")

    copy_sample_data()