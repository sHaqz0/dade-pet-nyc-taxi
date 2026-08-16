-- ИСПРАВЛЕНО: fare/distance — отношение, уязвимо к выбросам при
-- почти нулевой дистанции. Фильтр trip_distance >= 0.1 вместо
-- greatest(trip_distance, 0.01), median вместо avg.

-- 1. Временной ряд: спрос и медианная цена за милю, по часам
SELECT
    toHour(pickup_datetime) AS pickup_hour,
    count() AS pickup_count,
    quantile(0.5)(fare_amount / trip_distance) AS median_price_per_mile
FROM fact_trips
WHERE trip_distance >= 0.1
GROUP BY pickup_hour
ORDER BY pickup_hour;


-- 2. Детализация по районам (Borough)
SELECT
    dictGet('dim_location_dict', 'borough', pickup_location_id) AS pickup_borough,
    toHour(pickup_datetime) AS pickup_hour,
    count() AS pickup_count,
    quantile(0.5)(fare_amount / trip_distance) AS median_price_per_mile
FROM fact_trips
WHERE trip_distance >= 0.1
  AND fare_amount > 0
  AND trip_distance < 100
GROUP BY pickup_borough, pickup_hour
ORDER BY pickup_borough, pickup_hour;