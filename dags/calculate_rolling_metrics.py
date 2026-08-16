from airflow import DAG
from airflow.decorators import task
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.models import Variable
from datetime import datetime, timedelta
import clickhouse_connect


def get_ch_client():
    return clickhouse_connect.get_client(
        host=Variable.get("CLICKHOUSE_HOST", default_var="clickhouse"),
        port=int(Variable.get("CLICKHOUSE_PORT", default_var="8123")),
    )


with DAG(
    dag_id="calculate_rolling_metrics",
    start_date=datetime(2024, 1, 1),
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    tags=["metrics"],
) as dag:

    @task
    def calculate_window_metrics(n_days: int = None):
        # n — аргумент функции; если не передан явно, берём из Airflow Variable
        n = n_days or int(Variable.get("METRICS_WINDOW_DAYS", default_var="7"))

        ch_client = get_ch_client()
        max_loaded = ch_client.query(
            "SELECT maxOrNull(toDate(pickup_datetime)) FROM fact_trips"
        ).result_rows[0][0]

        if max_loaded is None:
            print("fact_trips пуста, считать нечего")
            return

        pg_hook = PostgresHook(postgres_conn_id="postgres_source")
        max_source_date = pg_hook.get_first(
            "SELECT max(pickup_datetime::date) FROM trips_raw"
        )[0]

        # ключевое ограничение из задания: не выходим за пределы сырых данных
        window_end = min(max_loaded + timedelta(days=n), max_source_date)

        ch_client.command(f"""
            INSERT INTO metrics_summary
            SELECT
                today() AS computed_at,
                toDate('{max_loaded}') AS window_start,
                toDate('{window_end}') AS window_end,
                taxi_type,
                count() AS trips_count,
                sum(total_amount) AS total_revenue,
                avg(total_amount) AS avg_trip_amount
            FROM fact_trips
            WHERE toDate(pickup_datetime) BETWEEN '{max_loaded}' AND '{window_end}'
            GROUP BY taxi_type
        """)
        print(f"Метрики посчитаны за окно {max_loaded} — {window_end} (запрошено {n} дней)")

    calculate_window_metrics()