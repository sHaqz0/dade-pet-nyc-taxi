import pandas as pd
from sqlalchemy import create_engine

# Подключение к Postgres (логин/пароль/база — те, что задали в docker-compose.yml)
engine = create_engine("postgresql+psycopg2://taxi_user:taxi_pass@localhost:5432/taxi_db")

# Список файлов и в какую таблицу каждый грузить
files_and_tables = [
    ("yellow_tripdata_2024-01.parquet", "yellow_tripdata"),
    ("yellow_tripdata_2024-04.parquet", "yellow_tripdata"),
    ("yellow_tripdata_2024-07.parquet", "yellow_tripdata"),
    ("green_tripdata_2024-01.parquet", "green_tripdata"),
    ("green_tripdata_2024-04.parquet", "green_tripdata"),
    ("green_tripdata_2024-07.parquet", "green_tripdata"),
]

for filename, table_name in files_and_tables:
    print(f"Читаю {filename}...")
    df = pd.read_parquet(filename)

    print(f"Загружаю {len(df)} строк в таблицу {table_name}...")
    df.to_sql(
        table_name,
        engine,
        if_exists="append",   # добавлять к таблице, а не пересоздавать её каждый раз
        index=False,
        chunksize=50000,      # грузим пачками по 50000 строк, а не всё разом
    )
    print(f"Готово: {filename} -> {table_name}\n")

print("Все файлы загружены!")