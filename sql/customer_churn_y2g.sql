-- Customer churn Yellow -> Green: эвристика через "сигнатуру поездки"
-- (зона посадки, зона высадки, способ оплаты, час дня), т.к. реального
-- ID пассажира в датасете TLC нет.
-- ОГРАНИЧЕНИЕ МЕТОДА: возможны false positives (разные люди с одинаковым
-- паттерном) и false negatives (тот же человек сменил маршрут/оплату/час).

WITH trip_signatures AS (
    SELECT DISTINCT
        pickup_location_id,
        dropoff_location_id,
        payment_type,
        toHour(pickup_datetime) AS pickup_hour,
        taxi_type,
        toYYYYMM(pickup_datetime) AS trip_month
    FROM fact_trips
    WHERE payment_type NOT IN ('Unknown', 'Cash')  -- Cash слишком шумный сигнал, много совпадений случайно
),

yellow_early AS (
    SELECT pickup_location_id, dropoff_location_id, payment_type, pickup_hour
    FROM trip_signatures WHERE taxi_type = 'yellow' AND trip_month = 202401
),
green_late AS (
    SELECT pickup_location_id, dropoff_location_id, payment_type, pickup_hour
    FROM trip_signatures WHERE taxi_type = 'green' AND trip_month = 202407
),
yellow_late AS (
    SELECT pickup_location_id, dropoff_location_id, payment_type, pickup_hour
    FROM trip_signatures WHERE taxi_type = 'yellow' AND trip_month = 202407
)

SELECT
    count() AS yellow_signatures_january,
    countIf((pickup_location_id, dropoff_location_id, payment_type, pickup_hour) IN (
        SELECT pickup_location_id, dropoff_location_id, payment_type, pickup_hour FROM green_late
    )) AS also_seen_in_green_july,
    countIf((pickup_location_id, dropoff_location_id, payment_type, pickup_hour) IN (
        SELECT pickup_location_id, dropoff_location_id, payment_type, pickup_hour FROM yellow_late
    )) AS also_seen_in_yellow_july,
    countIf(
        (pickup_location_id, dropoff_location_id, payment_type, pickup_hour) IN (
            SELECT pickup_location_id, dropoff_location_id, payment_type, pickup_hour FROM green_late
        )
        AND (pickup_location_id, dropoff_location_id, payment_type, pickup_hour) NOT IN (
            SELECT pickup_location_id, dropoff_location_id, payment_type, pickup_hour FROM yellow_late
        )
    ) AS likely_migrated_to_green
FROM yellow_early;