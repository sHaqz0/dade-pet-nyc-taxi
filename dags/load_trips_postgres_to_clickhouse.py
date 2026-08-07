from airflow import DAG
from airflow.decorators import task
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.models import Variable
from datetime import datetime, timedelta
import clickhouse_connect

VENDOR_MAP = {1: "Creative Mobile Technologies", 2: "VeriFone Inc."}
PAYMENT_MAP = {1: "Credit card", 2: "Cash", 3: "No charge", 4: "Dispute", 5: "Unknown", 6: "Voided trip"}
RATECODE_MAP = {1: "Standard rate", 2: "JFK", 3: "Newark", 4: "Nassau or Westchester", 5: "Negotiated fare", 6: "Group ride"}


def get_ch_client():
    return clickhouse_connect.get_client(
        host=Variable.get("CLICKHOUSE_HOST", default_var="clickhouse"),
        port=int(Variable.get("CLICKHOUSE_PORT", default_var="8123")),
    )


with DAG(
    dag_id="load_trips_postgres_to_clickhouse",
    start_date=datetime(2024, 1, 1),
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=5)},
    tags=["elt"],
) as dag:

    @task
    def get_next_date_to_load() -> str:
        ch_client = get_ch_client()
        # maxOrNull — важно: обычный max() на пустой таблице в ClickHouse
        # вернёт значение по умолчанию (1970-01-01), а не NULL
        result = ch_client.query("SELECT maxOrNull(toDate(pickup_datetime)) FROM fact_trips")
        max_loaded_date = result.result_rows[0][0]

        pg_hook = PostgresHook(postgres_conn_id="postgres_source")
        if max_loaded_date is None:
            # Ищем первую дату НЕ РАШЕ 2024 ГОДА
            row = pg_hook.get_first(
                "SELECT min(pickup_datetime::date) FROM trips_raw WHERE pickup_datetime >= '2024-01-01'")
        else:
            row = pg_hook.get_first(
                "SELECT min(pickup_datetime::date) FROM trips_raw WHERE pickup_datetime::date > %(last)s AND pickup_datetime >= '2024-01-01'",
                parameters={"last": max_loaded_date},
            )

        next_date = row[0] if row else None
        if next_date is None:
            raise ValueError("Все доступные дни из источника уже загружены")

        return next_date.strftime("%Y-%m-%d")

    @task
    def load_day(day: str):
        pg_hook = PostgresHook(postgres_conn_id="postgres_source")

        print(f"Выкачиваем данные из Postgres за {day}...")
        df = pg_hook.get_pandas_df(
            "SELECT * FROM trips_raw WHERE pickup_datetime::date = %(day)s",
            parameters={"day": day},
        )

        if df.empty:
            print(f"За {day} нет данных, пропускаем")
            return

        print(f"Прочитано {len(df)} строк. Начинаем подготовку...")

        fact_df = df[[
            "taxi_type", "pickup_datetime", "dropoff_datetime",
            "trip_distance", "fare_amount", "tip_amount", "total_amount",
            "extra", "mta_tax", "tolls_amount", "improvement_surcharge",
            "congestion_surcharge", "airport_fee",
        ]].copy()

        # Векторный маппинг
        fact_df["vendor_id"] = df["vendor_id"].map(VENDOR_MAP).fillna("Unknown")
        fact_df["pickup_location_id"] = df["pickup_location_id"].fillna(0).astype("uint32")
        fact_df["dropoff_location_id"] = df["dropoff_location_id"].fillna(0).astype("uint32")
        fact_df["passenger_count"] = df["passenger_count"].fillna(0).astype("uint8")
        fact_df["payment_type"] = df["payment_type"].map(PAYMENT_MAP).fillna("Unknown")
        fact_df["ratecode"] = df["ratecode_id"].map(RATECODE_MAP).fillna("Unknown")

        # Быстрая очистка trip_type без тяжелого .apply()
        fact_df["trip_type"] = df["trip_type"].fillna("").astype(str)
        fact_df["trip_type"] = fact_df["trip_type"].replace({"nan": None, "": None, "None": None})

        num_cols = ["trip_distance", "fare_amount", "tip_amount", "total_amount",
                    "extra", "mta_tax", "tolls_amount", "improvement_surcharge",
                    "congestion_surcharge"]
        for col in num_cols:
            fact_df[col] = fact_df[col].fillna(0).astype("float32")

        ch_client = get_ch_client()

        # Идемпотентность
        print(f"Удаляем старые данные за {day} из ClickHouse...")
        ch_client.command(f"ALTER TABLE fact_trips DELETE WHERE toDate(pickup_datetime) = '{day}'")

        # Вставляем батчами по 50 000 строк!
        batch_size = 50000
        total_rows = len(fact_df)
        print(f"Загружаем {total_rows} строк в ClickHouse батчами по {batch_size}...")

        for i in range(0, total_rows, batch_size):
            chunk = fact_df.iloc[i: i + batch_size]
            ch_client.insert_df("fact_trips", chunk)

        print(f"Успешно загружено {total_rows} строк за {day}")

    load_day(get_next_date_to_load())