-- Средняя скорость (миль/час) по часам суток и районам (borough)
SELECT
    toHour(pickup_datetime) AS pickup_hour,
    dictGet('dim_location_dict', 'borough', pickup_location_id) AS pickup_borough,
    avg(trip_distance / greatest(dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0, 0.01)) AS avg_speed_mph,
    count() AS trips_count
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime AND trip_distance > 0
GROUP BY pickup_hour, pickup_borough
ORDER BY pickup_hour, pickup_borough;

-- Распределение длительности поездок по районам (медиана, 90-й, 99-й перцентиль)
SELECT
    dictGet('dim_location_dict', 'borough', pickup_location_id) AS pickup_borough,
    quantiles(0.5, 0.9, 0.99)(dateDiff('second', pickup_datetime, dropoff_datetime) / 60.0) AS duration_minutes_p50_p90_p99
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
GROUP BY pickup_borough;

-- "Востребованность" зоны: сколько поездок в час она генерирует в среднем
SELECT
    dictGet('dim_location_dict', 'borough', pickup_location_id) AS pickup_borough,
    toHour(pickup_datetime) AS pickup_hour,
    count() AS trips_count,
    avg(trip_distance) AS avg_distance_miles,
    avg(dateDiff('second', pickup_datetime, dropoff_datetime) / 60.0) AS avg_duration_minutes
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
GROUP BY pickup_borough, pickup_hour
ORDER BY pickup_borough, pickup_hour;