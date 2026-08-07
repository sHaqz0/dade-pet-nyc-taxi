import pandas as pd
import clickhouse_connect

df = pd.read_csv("taxi_zone_lookup.csv")
df.columns = ["location_id", "borough", "zone", "service_zone"]

# заполняем пустые значения во всех строковых колонках пустой строкой
df["borough"] = df["borough"].fillna("")
df["zone"] = df["zone"].fillna("")
df["service_zone"] = df["service_zone"].fillna("")

client = clickhouse_connect.get_client(host="localhost", port=8123)
client.insert_df("dim_location", df)

print(f"Загружено {len(df)} строк в dim_location")