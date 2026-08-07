-- ============================================================
-- Задача: "Доход водителей" (реализовано как earning potential /
-- доходность поездок, т.к. в датасете TLC нет ID водителя)
-- ============================================================

-- 1. Общая выручка по срезам: день, тип такси, зона посадки
SELECT
    toDate(pickup_datetime) AS trip_date,
    taxi_type,
    dictGet('dim_location_dict', 'zone', pickup_location_id) AS pickup_zone,
    count() AS trips_count,
    sum(total_amount) AS total_revenue,
    sum(fare_amount) AS total_fare,
    sum(tip_amount) AS total_tips
FROM fact_trips
GROUP BY trip_date, taxi_type, pickup_zone
ORDER BY trip_date, total_revenue DESC;

-- та же метрика, но по неделям и месяцам (для дашборда — разные уровни детализации)
SELECT
    toStartOfWeek(pickup_datetime) AS week,
    taxi_type,
    sum(total_amount) AS total_revenue
FROM fact_trips
GROUP BY week, taxi_type
ORDER BY week;


-- 2. Доходность в час — ключевая метрика для водителя:
-- сколько денег приносит час вождения, по часу суток и зоне посадки
SELECT
    toHour(pickup_datetime) AS pickup_hour,
    dictGet('dim_location_dict', 'zone', pickup_location_id) AS pickup_zone,
    avg(total_amount / greatest(dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0, 0.01)) AS avg_revenue_per_hour,
    count() AS trips_count
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime  -- отсекаем аномалии: нулевую/отрицательную длительность
GROUP BY pickup_hour, pickup_zone
ORDER BY avg_revenue_per_hour DESC
LIMIT 50;


-- 3. Доходность на милю — короткие vs длинные поездки
SELECT
    taxi_type,
    dictGet('dim_location_dict', 'zone', pickup_location_id) AS pickup_zone,
    avg(fare_amount / greatest(trip_distance, 0.01)) AS avg_revenue_per_mile,
    count() AS trips_count
FROM fact_trips
WHERE trip_distance > 0
GROUP BY taxi_type, pickup_zone
ORDER BY avg_revenue_per_mile DESC
LIMIT 20;


-- 4. Доля чаевых от суммы, по способу оплаты
-- Ограничение данных: наличные чаевые в системе почти не фиксируются
-- (водитель их просто не пробивает), поэтому низкий avg_tip_ratio у Cash —
-- это artefact сбора данных, а не реальное поведение пассажиров
SELECT
    payment_type,
    count() AS trips_count,
    avg(tip_amount / greatest(fare_amount, 0.01)) AS avg_tip_ratio,
    sum(tip_amount) AS total_tips,
    sum(fare_amount) AS total_fare
FROM fact_trips
WHERE fare_amount > 0
GROUP BY payment_type
ORDER BY avg_tip_ratio DESC;


-- 5. Топ-5 зон посадки по доходности в час
-- HAVING отсекает зоны с малым числом поездок — иначе редкая зона
-- с 3 поездками может случайно попасть в топ по среднему значению (шум малой выборки)
SELECT
    dictGet('dim_location_dict', 'zone', pickup_location_id) AS pickup_zone,
    avg(total_amount / greatest(dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0, 0.01)) AS avg_revenue_per_hour,
    count() AS trips_count
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
GROUP BY pickup_zone
HAVING trips_count > 1000
ORDER BY avg_revenue_per_hour DESC
LIMIT 5;