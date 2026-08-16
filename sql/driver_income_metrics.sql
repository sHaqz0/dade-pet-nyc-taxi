-- ============================================================
-- Задача: "Доход водителей" (earning potential), т.к. в датасете
-- TLC нет ID водителя.
--
-- ИСПРАВЛЕНИЕ (после находки на heatmap-графике блока 6):
-- Любая метрика вида "amount / duration" или "fare / distance" —
-- отношение — уязвима к экстремальным выбросам: поездка с
-- длительностью в пару секунд (сбой GPS/счётчика) при обычном
-- тарифе даёт нереалистичную экстраполяцию (десятки тысяч "$/час").
-- Раньше use "greatest(x, 0.01)" просто не давал делить на ноль,
-- но не защищал от абсурдных значений. Теперь: (1) отфильтровываем
-- поездки короче разумного порога ДО расчёта, (2) считаем median
-- вместо avg — она устойчива к редким выбросам, даже если фильтр
-- пропустит не всё.
-- Пороги: длительность >= 60 сек, дистанция >= 0.1 мили,
-- тариф >= $2.50 (минимальная посадочная такса) для чаевых.
-- ============================================================

-- 1. Общая выручка по срезам: день, тип такси, зона посадки
-- (sum() — деления нет, выбросам не подвержено, фикс не нужен)
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

-- выручка по неделям (фикс не нужен, тот же аргумент)
SELECT
    toStartOfWeek(pickup_datetime) AS week,
    taxi_type,
    count() AS trips_count,
    sum(total_amount) AS total_revenue,
    sum(fare_amount) AS total_fare,
    sum(tip_amount) AS total_tips
FROM fact_trips
GROUP BY week, taxi_type
ORDER BY week;

-- и по месяцам (фикс не нужен)
SELECT
    toStartOfMonth(pickup_datetime) AS month,
    taxi_type,
    count() AS trips_count,
    sum(total_amount) AS total_revenue,
    sum(fare_amount) AS total_fare,
    sum(tip_amount) AS total_tips
FROM fact_trips
GROUP BY month, taxi_type
ORDER BY month, taxi_type;


-- 2. Доходность в час — ИСПРАВЛЕНО: фильтр по длительности + медиана
SELECT
    toHour(pickup_datetime) AS pickup_hour,
    dictGet('dim_location_dict', 'zone', pickup_location_id) AS pickup_zone,
    quantile(0.5)(total_amount / (dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0)) AS median_revenue_per_hour,
    count() AS trips_count
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
  AND dateDiff('second', pickup_datetime, dropoff_datetime) >= 60
GROUP BY pickup_hour, pickup_zone
ORDER BY median_revenue_per_hour DESC
LIMIT 50;


-- 3. Доходность на милю — ИСПРАВЛЕНО: фильтр по дистанции + медиана
SELECT
    taxi_type,
    dictGet('dim_location_dict', 'zone', pickup_location_id) AS pickup_zone,
    quantile(0.5)(fare_amount / trip_distance) AS median_revenue_per_mile,
    count() AS trips_count
FROM fact_trips
WHERE trip_distance >= 0.1
GROUP BY taxi_type, pickup_zone
ORDER BY median_revenue_per_mile DESC
LIMIT 20;


-- 4. Доля чаевых от суммы — ИСПРАВЛЕНО: минимальный реалистичный тариф вместо >0
-- Ограничение данных остаётся в силе: наличные чаевые почти не фиксируются
SELECT
    payment_type,
    count() AS trips_count,
    quantile(0.5)(tip_amount / fare_amount) AS median_tip_ratio,
    sum(tip_amount) AS total_tips,
    sum(fare_amount) AS total_fare
FROM fact_trips
WHERE fare_amount >= 2.5
GROUP BY payment_type
ORDER BY median_tip_ratio DESC;


-- 5. Топ-5 зон посадки по доходности в час — ИСПРАВЛЕНО: медиана + фильтр
-- HAVING по-прежнему нужен (защита от малой выборки — другая, но тоже
-- реальная проблема, независимая от выбросов)
SELECT
    dictGet('dim_location_dict', 'zone', pickup_location_id) AS pickup_zone,
    quantile(0.5)(total_amount / (dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0)) AS median_revenue_per_hour,
    count() AS trips_count
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
  AND dateDiff('second', pickup_datetime, dropoff_datetime) >= 60
GROUP BY pickup_zone
HAVING trips_count > 1000
ORDER BY median_revenue_per_hour DESC
LIMIT 5;

-- 6. Тепловая карта доходности: День недели x Час суток — ИСПРАВЛЕНО (уже обсуждали)
SELECT
    toDayOfWeek(pickup_datetime) AS day_of_week,
    toHour(pickup_datetime) AS pickup_hour,
    quantile(0.5)(total_amount / (dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0)) AS median_hourly_rate,
    count() AS total_trips
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
  AND dateDiff('second', pickup_datetime, dropoff_datetime) >= 60
GROUP BY day_of_week, pickup_hour
ORDER BY day_of_week, pickup_hour;


-- 7. Yellow vs Green — ИСПРАВЛЕНО: оба отношения через медиану + фильтры
SELECT
    taxi_type,
    quantile(0.5)(total_amount / (dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0)) AS median_revenue_per_hour,
    count() AS trips_count
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
  AND dateDiff('second', pickup_datetime, dropoff_datetime) >= 60
GROUP BY taxi_type;

SELECT
    taxi_type,
    quantile(0.5)(fare_amount / trip_distance) AS median_revenue_per_mile,
    count() AS trips_count
FROM fact_trips
WHERE trip_distance >= 0.1
GROUP BY taxi_type;


-- 8. Будни vs выходные — ИСПРАВЛЕНО
SELECT
    taxi_type,
    if(toDayOfWeek(pickup_datetime) IN (6, 7), 'weekend', 'weekday') AS day_type,
    quantile(0.5)(total_amount / (dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0)) AS median_revenue_per_hour,
    count() AS trips_count
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
  AND dateDiff('second', pickup_datetime, dropoff_datetime) >= 60
GROUP BY taxi_type, day_type;

-- 9. Общий тренд доходности по часам суток — ИСПРАВЛЕНО
SELECT
    toHour(pickup_datetime) AS pickup_hour,
    quantile(0.5)(total_amount / (dateDiff('second', pickup_datetime, dropoff_datetime) / 3600.0)) AS median_revenue_per_hour,
    count() AS trips_count
FROM fact_trips
WHERE dropoff_datetime > pickup_datetime
  AND dateDiff('second', pickup_datetime, dropoff_datetime) >= 60
GROUP BY pickup_hour
ORDER BY pickup_hour;