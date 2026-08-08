-- Временной ряд: спрос (кол-во поездок) и эффективная цена за милю, по часам
-- Глобальный гистерезис по всему Нью-Йорку
SELECT
    toHour(pickup_datetime) AS pickup_hour,
    count() AS pickup_count,
    avg(fare_amount / greatest(trip_distance, 0.01)) AS avg_price_per_mile
FROM fact_trips
WHERE trip_distance > 0
GROUP BY pickup_hour
ORDER BY pickup_hour;


-- 2. Детализация по районам (Borough) — для сравнения эластичности в разных частях города
SELECT
    dictGet('dim_location_dict', 'borough', pickup_location_id) AS pickup_borough,
    toHour(pickup_datetime) AS pickup_hour,
    count() AS pickup_count,
    avg(fare_amount / greatest(trip_distance, 0.01)) AS avg_price_per_mile
FROM fact_trips
WHERE trip_distance > 0
  AND fare_amount > 0
  AND trip_distance < 100
GROUP BY pickup_borough, pickup_hour
ORDER BY pickup_borough, pickup_hour;