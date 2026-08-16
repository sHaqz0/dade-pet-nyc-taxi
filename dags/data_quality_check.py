from airflow import DAG
from airflow.decorators import task
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.models import Variable
from datetime import datetime
import clickhouse_connect


def get_ch_client():
    return clickhouse_connect.get_client(
        host=Variable.get("CLICKHOUSE_HOST", default_var="clickhouse"),
        port=int(Variable.get("CLICKHOUSE_PORT", default_var="8123")),
    )


CHECKS = {
    "invalid_duration": "dropoff_datetime <= pickup_datetime",
    "negative_amounts": "total_amount < 0 OR fare_amount < 0",
    "negative_distance": "trip_distance < 0",
    "missing_pickup_zone": "pickup_location_id = 0",
    "missing_dropoff_zone": "dropoff_location_id = 0",
    "extreme_distance": "trip_distance > 100",
    "extreme_amount": "total_amount > 500",
}

FAIL_THRESHOLD = 0.01  # больше 1% "плохих" строк -> статус FAIL, иначе WARNING


with DAG(
    dag_id="data_quality_check",
    start_date=datetime(2024, 1, 1),
    schedule="@hourly",
    catchup=False,
    max_active_runs=1,
    tags=["data_quality"],
) as dag:

    @task
    def run_quality_checks():
        ch_client = get_ch_client()

        countif_exprs = ", ".join(f"countIf({cond}) AS {name}" for name, cond in CHECKS.items())
        row = ch_client.query(f"SELECT count() AS total_rows, {countif_exprs} FROM fact_trips").result_rows[0]

        total_rows = row[0]
        checked_at = datetime.utcnow()

        results = []
        for i, name in enumerate(CHECKS.keys(), start=1):
            failed = row[i]
            ratio = failed / total_rows if total_rows else 0
            status = "OK" if failed == 0 else ("FAIL" if ratio > FAIL_THRESHOLD else "WARNING")
            results.append((checked_at, name, total_rows, failed, ratio, status))

        ch_client.insert(
            "dq_check_log",
            results,
            column_names=["checked_at", "check_name", "total_rows", "failed_rows", "fail_ratio", "status"],
        )

        bad = [r for r in results if r[5] != "OK"]
        print(f"Проверки завершены. Проблемных: {len(bad)} из {len(results)}" if bad else "Все проверки чистые")

    @task
    def check_source_target_lag():
        ch_client = get_ch_client()
        max_loaded = ch_client.query("SELECT maxOrNull(toDate(pickup_datetime)) FROM fact_trips").result_rows[0][0]

        pg_hook = PostgresHook(postgres_conn_id="postgres_source")
        max_source = pg_hook.get_first("SELECT max(pickup_datetime::date) FROM trips_raw")[0]

        if max_loaded is None or max_source is None:
            return

        lag_days = (max_source - max_loaded).days
        status = "OK" if lag_days <= 1 else ("WARNING" if lag_days <= 7 else "FAIL")

        ch_client.insert(
            "dq_check_log",
            [(datetime.utcnow(), "source_target_lag_days", 1, lag_days, float(lag_days), status)],
            column_names=["checked_at", "check_name", "total_rows", "failed_rows", "fail_ratio", "status"],
        )
        print(f"Отставание источник/приёмник: {lag_days} дн., статус {status}")

    run_quality_checks()
    check_source_target_lag()