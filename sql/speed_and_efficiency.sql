-- ИСПРАВЛЕНО в запросе скорости: distance/duration — отношение,
-- уязвимо при почти нулевой длительности. Фильтр по длительности
-- >= 60 сек вместо greatest(duration, 0.01), median вместо avg.
-- Остальные два запроса не изменились: #2 уже использует quantile
-- изначально (устойчиво), #3 считает avg от сырых значений, а не
-- от отношения — риск ниже, добавил лёгкую гигиену (разумные пределы).

-- 1. Медианная скорость (миль/час) по часам суток и районам
SELECT
    toHour(pickup_datetime) AS pickup_hour,
    dictGet('dim_location_dict', 'borough', pickup_location_id) AS pickup_borough,
    quantile(0.5)(trip_distance / (dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0)) AS median_speed_mph,
    count() AS trips_count
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
  AND dateDiff('second', pickup_datetime, dropoff_datetime) >= 60
  AND trip_distance > 0
GROUP BY pickup_hour, pickup_borough
ORDER BY pickup_hour, pickup_borough;

-- Распределение длительности поездок (без изменений — уже устойчиво)
SELECT
    dictGet('dim_location_dict', 'borough', pickup_location_id) AS pickup_borough,
    quantiles(0.5, 0.9, 0.99)(dateDiff('second', pickup_datetime, dropoff_datetime) / 60.0) AS duration_minutes_p50_p90_p99
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
GROUP BY pickup_borough;

-- "Востребованность" зоны — добавлена лёгкая гигиена данных
-- (те же пределы, что используем как DQ-проверки в блоке 5:
-- extreme_distance/extreme_amount), но это не тот же класс проблемы,
-- фикс опциональный, а не обязательный
SELECT
    dictGet('dim_location_dict', 'borough', pickup_location_id) AS pickup_borough,
    toHour(pickup_datetime) AS pickup_hour,
    count() AS trips_count,
    avg(trip_distance) AS avg_distance_miles,
    avg(dateDiff('second', pickup_datetime, dropoff_datetime) / 60.0) AS avg_duration_minutes
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
  AND trip_distance <= 100
GROUP BY pickup_borough, pickup_hour
ORDER BY pickup_borough, pickup_hour;