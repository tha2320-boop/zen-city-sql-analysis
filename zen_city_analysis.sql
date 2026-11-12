-- ********************************************************
-- INITIAL DATA PROFILING
-- Checking total volume, unique trips,date ranges and null
-- ********************************************************
-- First Impression of the tables
SELECT *
FROM `bqproj26.zen_city.station_info`
LIMIT 20;

SELECT *
FROM `bqproj26.zen_city.rentals`
LIMIT 20;

--  Primary checks on station.info table
SELECT
    COUNT(*) AS total_rows, --102
    COUNT(DISTINCT station_id) AS unique_stations, --102
    COUNTIF(station_id IS NULL) AS null_stations,--0
    COUNTIF(status IS NULL) AS null_status,--0
    COUNTIF(number_of_docks IS NULL OR number_of_docks <= 0) AS invalid_docks, --20
    MIN(number_of_docks) AS min_docks, --4
    MAX(number_of_docks) AS max_docks, --22
    AVG(number_of_docks) AS avg_docks -- 13.46
FROM `bqproj26.zen_city.station_info`;

-- Primary checks on rentals table
SELECT
    COUNT(*) AS total_trips,--16585
    COUNT(DISTINCT trip_id) AS unique_trips, --16585
    MIN(start_time) AS min_start_time, -- 01/01/2022
    MAX(start_time) AS max_start_time, -- 31/03/2022
    COUNT(DISTINCT bike_id) AS unique_bikes, --580
-- nulls
    COUNTIF(trip_id IS NULL) AS null_trips,--0
    COUNTIF(start_station_id IS NULL) AS null_start_stations,--0
    COUNTIF(end_station_id IS NULL) AS null_end_stations, --1
    COUNTIF(duration_minutes IS NULL) AS null_duration, --0
-- duration
    COUNTIF(duration_minutes <= 0) AS zero_or_negative_duration,--0
    COUNTIF(duration_minutes < 2) AS trips_under_2_min,--0
    COUNTIF(duration_minutes > 1440) AS trips_over_24_hours --6
FROM `bqproj26.zen_city.rentals`;

-- ********************************************************
-- STATION NETWORK OVERVIEW
-- Identifying active stations vs. stations actually used
-- ********************************************************

-- Part A: Total active stations in the system (Returns 78)
WITH active_stations AS (
  SELECT station_id
  FROM `bqproj26.zen_city.station_info`
  WHERE LOWER(TRIM(status)) = 'active'
)
SELECT COUNT(*) AS total_active_stations
FROM active_stations;

-- Part B: Actual stations used in Q1 (Reveals the network asymmetry):
SELECT
  COUNT(DISTINCT start_station_id) AS unique_start_stations, -- Returns 10
  COUNT(DISTINCT end_station_id) AS unique_end_stations      -- Returns 80
FROM `bqproj26.zen_city.rentals`
WHERE start_station_id IS NOT NULL
  AND end_station_id IS NOT NULL;


-- ********************************************************
-- THE MASTER CLEANING CTE
-- Resolving inconsistencies, handling nulls, and treating outliers
-- fixing the stations with mis-match id's
-- ********************************************************

WITH station_crosswalk AS (
  -- Crosswalk table to resolve inconsistent station IDs found during EDA
  SELECT * FROM UNNEST([
    STRUCT(4938 AS rentals_station_id, 11   AS station_info_id),
    STRUCT(7125 AS rentals_station_id, 111  AS station_info_id),
    STRUCT(7188 AS rentals_station_id, 3792 AS station_info_id),
    STRUCT(7131 AS rentals_station_id, 1111 AS station_info_id),
    STRUCT(7190 AS rentals_station_id, 2545 AS station_info_id),
    STRUCT(7187 AS rentals_station_id, 0    AS station_info_id)
  ])
),

deduplicated_rentals AS (
  -- Identify and flag duplicate trip records
  SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY start_time ASC) AS row_num
  FROM `bqproj26.zen_city.rentals`
),

cleaned_rentals AS (
  -- Treat nulls, filter outliers, and apply standardized station IDs
  SELECT
    d.trip_id,
    CAST(d.start_time AS TIMESTAMP) AS start_time,
    d.bike_id,
    CASE
      WHEN d.subscriber_type IN ('Student Membership', 'U.T. Student Membership')
        THEN 'Student Membership'
      ELSE d.subscriber_type
    END AS subscriber_type,
    COALESCE(cs_start.station_info_id, d.start_station_id) AS start_station_id,
    COALESCE(cs_end.station_info_id, d.end_station_id) AS end_station_id,
    d.duration_minutes
  FROM deduplicated_rentals d
  LEFT JOIN station_crosswalk cs_start ON d.start_station_id = cs_start.rentals_station_id
  LEFT JOIN station_crosswalk cs_end ON d.end_station_id = cs_end.rentals_station_id
  WHERE d.row_num = 1
    AND d.start_station_id IS NOT NULL
    AND d.end_station_id IS NOT NULL
    AND d.duration_minutes <= 1440
)

-- Add station names to the clean dataset for Analysis
-- every station name in this script comes from
-- station_info.name via the station_id join.


SELECT
  c.trip_id,c.start_time,c.bike_id,
  c.subscriber_type,c.start_station_id,
  s_start.name AS start_station_name,c.end_station_id,
  s_end.name AS end_station_name,c.duration_minutes
FROM cleaned_rentals c
LEFT JOIN `bqproj26.zen_city.station_info` s_start
  ON c.start_station_id = s_start.station_id
LEFT JOIN `bqproj26.zen_city.station_info` s_end
  ON c.end_station_id = s_end.station_id;

-- ----------------------------------------------------------------------------
-- Business Question: Which stations are overcrowded and which are underutilized?
-- Metric: Traffic per Dock (Total Start & End movements / Number of Docks)
-- ----------------------------------------------------------------------------

WITH station_crosswalk AS (
  SELECT * FROM UNNEST([
    STRUCT(4938 AS rentals_station_id, 11   AS station_info_id),
    STRUCT(7125 AS rentals_station_id, 111  AS station_info_id),
    STRUCT(7188 AS rentals_station_id, 3792 AS station_info_id),
    STRUCT(7131 AS rentals_station_id, 1111 AS station_info_id),
    STRUCT(7190 AS rentals_station_id, 2545 AS station_info_id),
    STRUCT(7187 AS rentals_station_id, 0    AS station_info_id)
  ])
),

deduplicated_rentals AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY start_time ASC) AS row_num
  FROM `bqproj26.zen_city.rentals`
),

cleaned_rentals AS (
  SELECT
    d.trip_id,
    CAST(d.start_time AS TIMESTAMP) AS start_time,
    d.bike_id,
    CASE
      WHEN d.subscriber_type IN ('Student Membership', 'U.T. Student Membership')
        THEN 'Student Membership'
      ELSE d.subscriber_type
    END AS subscriber_type,
    COALESCE(cs_start.station_info_id, d.start_station_id) AS start_station_id,
    COALESCE(cs_end.station_info_id, d.end_station_id) AS end_station_id,
    d.duration_minutes
  FROM deduplicated_rentals d
  LEFT JOIN station_crosswalk cs_start ON d.start_station_id = cs_start.rentals_station_id
  LEFT JOIN station_crosswalk cs_end ON d.end_station_id = cs_end.rentals_station_id
  WHERE d.row_num = 1
    AND d.start_station_id IS NOT NULL
    AND d.end_station_id IS NOT NULL
    AND d.duration_minutes <= 1440
),

station_traffic AS (
  SELECT station_id, COUNT(*) AS total_movements
  FROM (
    SELECT start_station_id AS station_id FROM cleaned_rentals
    UNION ALL
    SELECT end_station_id AS station_id FROM cleaned_rentals
  )
  GROUP BY station_id
)

SELECT
  s.station_id,
  s.name AS station_name,
  s.number_of_docks,
  COALESCE(t.total_movements, 0) AS total_q1_traffic,

  -- Business Metric: Traffic per dock (how many trips utilized a single dock)
  ROUND(COALESCE(t.total_movements, 0) / NULLIF(s.number_of_docks, 0), 2) AS traffic_per_dock,

  -- Station footprint data to assess physical capacity for adding/removing docks
  s.footprint_length, s.footprint_width,

  -- Automated business categorization for actionable recommendations.
  -- Invalid dock counts (NULL or <=0, ~20% of all stations per profiling)
  -- are flagged explicitly instead of silently falling into 'Balanced'.
  --
  -- Threshold validation (see distribution diagnostic query): across all 78
  -- active stations, mean=31.1 and stddev=70.8, so mean + 1 stddev = 101.9 --
  -- closely matching the 100 cutoff used here for "Overcrowded" (a standard
  -- statistical-outlier boundary). The 10 cutoff for "Underutilized" doesn't
  -- align with a round percentile, but the distribution is effectively
  -- bimodal: P75 = 6.1 and P90 = 121.5, so almost no station actually sits
  -- near a value of 10 -- the classification is stable regardless of the
  -- exact cutoff chosen inside that empty range.


  CASE
    WHEN s.number_of_docks IS NULL OR s.number_of_docks <= 0
      THEN 'Data Quality Issue - No Valid Dock Count'
    WHEN ROUND(COALESCE(t.total_movements, 0) / NULLIF(s.number_of_docks, 0), 2) > 100
      THEN 'Overcrowded'
    WHEN ROUND(COALESCE(t.total_movements, 0) / NULLIF(s.number_of_docks, 0), 2) < 10
      THEN 'Underutilized'
    ELSE 'Balanced'
  END AS business_recommendation

FROM `bqproj26.zen_city.station_info` s
LEFT JOIN station_traffic t ON s.station_id = t.station_id
WHERE LOWER(TRIM(s.status)) = 'active'
ORDER BY traffic_per_dock DESC;

-- ********************************************************
-- Business Question: Of the overcrowded stations, which are being drained
-- fastest - i.e. where should nightly rebalancing routes prioritize
-- returning bikes? Departures-only, not combined traffic, since rebalancing
-- is about restocking stations that are losing bikes.
-- Metric: Departures per Dock (Start-only movements / Number of Docks)
-- ********************************************************

WITH station_crosswalk AS (
  SELECT * FROM UNNEST([
    STRUCT(4938 AS rentals_station_id, 11   AS station_info_id),
    STRUCT(7125 AS rentals_station_id, 111  AS station_info_id),
    STRUCT(7188 AS rentals_station_id, 3792 AS station_info_id),
    STRUCT(7131 AS rentals_station_id, 1111 AS station_info_id),
    STRUCT(7190 AS rentals_station_id, 2545 AS station_info_id),
    STRUCT(7187 AS rentals_station_id, 0    AS station_info_id)
  ])
),

deduplicated_rentals AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY start_time ASC) AS row_num
  FROM `bqproj26.zen_city.rentals`
),

cleaned_rentals AS (
  SELECT
    d.trip_id,
    CAST(d.start_time AS TIMESTAMP) AS start_time,
    d.bike_id,
    CASE
      WHEN d.subscriber_type IN ('Student Membership', 'U.T. Student Membership')
        THEN 'Student Membership'
      ELSE d.subscriber_type
    END AS subscriber_type,
    COALESCE(cs_start.station_info_id, d.start_station_id) AS start_station_id,
    COALESCE(cs_end.station_info_id, d.end_station_id) AS end_station_id,
    d.duration_minutes
  FROM deduplicated_rentals d
  LEFT JOIN station_crosswalk cs_start ON d.start_station_id = cs_start.rentals_station_id
  LEFT JOIN station_crosswalk cs_end ON d.end_station_id = cs_end.rentals_station_id
  WHERE d.row_num = 1
    AND d.start_station_id IS NOT NULL
    AND d.end_station_id IS NOT NULL
    AND d.duration_minutes <= 1440
),

station_departures AS (
  SELECT start_station_id AS station_id, COUNT(*) AS total_departures
  FROM cleaned_rentals
  GROUP BY start_station_id
)

SELECT
  s.station_id,
  s.name AS station_name,
  s.number_of_docks,
  COALESCE(d.total_departures, 0) AS total_q1_departures,
  ROUND(COALESCE(d.total_departures, 0) / NULLIF(s.number_of_docks, 0), 2) AS departures_per_dock
FROM `bqproj26.zen_city.station_info` s
LEFT JOIN station_departures d ON s.station_id = d.station_id
WHERE LOWER(TRIM(s.status)) = 'active'
  AND s.number_of_docks > 0
  AND d.total_departures IS NOT NULL   -- only the 10 stations actually used as an origin
ORDER BY departures_per_dock DESC
LIMIT 10;


-- ********************************************************
-- Business Question: When during the day is origin-station traffic lowest,
-- so nightly rebalancing trucks can restock the top 10 origin stations
-- without competing with live demand, and finish before the morning surge?
-- Metric: Total trips per hour of day, across all stations, Q1 2022
-- (Supports the 01:00-06:00 rebalancing-window recommendation.)
-- ********************************************************

WITH station_crosswalk AS (
  SELECT * FROM UNNEST([
    STRUCT(4938 AS rentals_station_id, 11   AS station_info_id),
    STRUCT(7125 AS rentals_station_id, 111  AS station_info_id),
    STRUCT(7188 AS rentals_station_id, 3792 AS station_info_id),
    STRUCT(7131 AS rentals_station_id, 1111 AS station_info_id),
    STRUCT(7190 AS rentals_station_id, 2545 AS station_info_id),
    STRUCT(7187 AS rentals_station_id, 0    AS station_info_id)
  ])
),

deduplicated_rentals AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY start_time ASC) AS row_num
  FROM `bqproj26.zen_city.rentals`
),

cleaned_rentals AS (
  SELECT
    d.trip_id,
    CAST(d.start_time AS TIMESTAMP) AS start_time,
    d.bike_id,
    CASE
      WHEN d.subscriber_type IN ('Student Membership', 'U.T. Student Membership')
        THEN 'Student Membership'
      ELSE d.subscriber_type
    END AS subscriber_type,
    COALESCE(cs_start.station_info_id, d.start_station_id) AS start_station_id,
    COALESCE(cs_end.station_info_id, d.end_station_id) AS end_station_id,
    d.duration_minutes
  FROM deduplicated_rentals d
  LEFT JOIN station_crosswalk cs_start ON d.start_station_id = cs_start.rentals_station_id
  LEFT JOIN station_crosswalk cs_end ON d.end_station_id = cs_end.rentals_station_id
  WHERE d.row_num = 1
    AND d.start_station_id IS NOT NULL
    AND d.end_station_id IS NOT NULL
    AND d.duration_minutes <= 1440
)

-- Business Metric: trip volume by hour of day, to identify the system's
-- lowest-activity window for nightly rebalancing
SELECT
  EXTRACT(HOUR FROM start_time) AS hour_of_day,
  COUNT(*) AS total_trips
FROM cleaned_rentals
GROUP BY hour_of_day
ORDER BY hour_of_day;


-- ********************************************************
-- Business Question: What is Zen City's rider composition by subscriber
-- type, and how much does the business depend on students specifically?
-- Metric: Share of total Q1 trips by subscriber_type
-- (This is the foundation for the 3-group behavioral rollup - Student /
-- Other Members / Casual & Short-term - used throughout the growth slides.)
-- ********************************************************

-- Business Metric: % share of Q1 trips per subscriber type
-- (subscriber_type is standardized inside cleaned_rentals, so 'Student
-- Membership' and 'U.T. Student Membership' are already one category here)

WITH station_crosswalk AS (
  SELECT * FROM UNNEST([
    STRUCT(4938 AS rentals_station_id, 11   AS station_info_id),
    STRUCT(7125 AS rentals_station_id, 111  AS station_info_id),
    STRUCT(7188 AS rentals_station_id, 3792 AS station_info_id),
    STRUCT(7131 AS rentals_station_id, 1111 AS station_info_id),
    STRUCT(7190 AS rentals_station_id, 2545 AS station_info_id),
    STRUCT(7187 AS rentals_station_id, 0    AS station_info_id)
  ])
),

deduplicated_rentals AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY start_time ASC) AS row_num
  FROM `bqproj26.zen_city.rentals`
),

cleaned_rentals AS (
  SELECT
    d.trip_id,
    CAST(d.start_time AS TIMESTAMP) AS start_time,
    d.bike_id,
    CASE
      WHEN d.subscriber_type IN ('Student Membership', 'U.T. Student Membership')
        THEN 'Student Membership'
      ELSE d.subscriber_type
    END AS subscriber_type,
    COALESCE(cs_start.station_info_id, d.start_station_id) AS start_station_id,
    COALESCE(cs_end.station_info_id, d.end_station_id) AS end_station_id,
    d.duration_minutes
  FROM deduplicated_rentals d
  LEFT JOIN station_crosswalk cs_start ON d.start_station_id = cs_start.rentals_station_id
  LEFT JOIN station_crosswalk cs_end ON d.end_station_id = cs_end.rentals_station_id
  WHERE d.row_num = 1
    AND d.start_station_id IS NOT NULL
    AND d.end_station_id IS NOT NULL
    AND d.duration_minutes <= 1440
)

SELECT
  subscriber_type,
  COUNT(*) AS total_trips,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_total_trips
FROM cleaned_rentals
GROUP BY subscriber_type
ORDER BY total_trips DESC;


-- ********************************************************
-- Business Question: Beyond the 77% headline, do non-student riders behave
-- like smaller copies of students, or are they a genuinely different
-- audience? Rolls the 10 raw subscriber_type values into 3 behavioral
-- segments and compares their timing and trip-length patterns.
-- Metric: Weekend share of trips (%) and median trip duration, by rider
-- segment (Student / Other Members / Casual & Short-term)
-- ********************************************************

WITH station_crosswalk AS (
  SELECT * FROM UNNEST([
    STRUCT(4938 AS rentals_station_id, 11   AS station_info_id),
    STRUCT(7125 AS rentals_station_id, 111  AS station_info_id),
    STRUCT(7188 AS rentals_station_id, 3792 AS station_info_id),
    STRUCT(7131 AS rentals_station_id, 1111 AS station_info_id),
    STRUCT(7190 AS rentals_station_id, 2545 AS station_info_id),
    STRUCT(7187 AS rentals_station_id, 0    AS station_info_id)
  ])
),

deduplicated_rentals AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY start_time ASC) AS row_num
  FROM `bqproj26.zen_city.rentals`
),

cleaned_rentals AS (
  SELECT
    d.trip_id,
    CAST(d.start_time AS TIMESTAMP) AS start_time,
    CASE
      WHEN d.subscriber_type IN ('Student Membership', 'U.T. Student Membership')
        THEN 'Student Membership'
      ELSE d.subscriber_type
    END AS subscriber_type,
    COALESCE(cs_start.station_info_id, d.start_station_id) AS start_station_id,
    COALESCE(cs_end.station_info_id, d.end_station_id) AS end_station_id,
    d.duration_minutes
  FROM deduplicated_rentals d
  LEFT JOIN station_crosswalk cs_start ON d.start_station_id = cs_start.rentals_station_id
  LEFT JOIN station_crosswalk cs_end ON d.end_station_id = cs_end.rentals_station_id
  WHERE d.row_num = 1
    AND d.start_station_id IS NOT NULL
    AND d.end_station_id IS NOT NULL
    AND d.duration_minutes <= 1440
),

segmented AS (
  -- Roll the 10 raw subscriber_type values up into 3 behavioral groups
  SELECT
    *,
    CASE
      WHEN subscriber_type = 'Student Membership' THEN 'Student'
      WHEN subscriber_type IN ('Local31', 'Local365', 'Annual Membership', 'HT Ram Membership')
        THEN 'Other Members'
      WHEN subscriber_type IN ('Pay-as-you-ride', 'Explorer', '3-Day Weekender',
                                '24 Hour Walk Up Pass', 'Single Trip (Pay-as-you-ride)')
        THEN 'Casual/Short-term'
      ELSE 'Other/Unclassified'
    END AS rider_segment,
    -- BigQuery DAYOFWEEK: 1 = Sunday ... 7 = Saturday
    EXTRACT(DAYOFWEEK FROM start_time) IN (1, 7) AS is_weekend
  FROM cleaned_rentals
)

SELECT
  rider_segment,
  COUNT(*) AS total_trips,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_total_trips,
  ROUND(COUNTIF(is_weekend) * 100.0 / COUNT(*), 1) AS weekend_pct,
  -- Median computed via APPROX_QUANTILES, once per segment (not nested
  -- inside a correlated subquery - see the earlier "aggregate in UNNEST"
  -- fix on the Traffic per Dock threshold diagnostic).
  APPROX_QUANTILES(duration_minutes, 100)[OFFSET(50)] AS median_duration_minutes
FROM segmented
GROUP BY rider_segment
ORDER BY total_trips DESC;


-- ********************************************************
-- Business Question: Within each rider segment, which stations do they
-- actually use - and does the Casual/Short-term pattern line up with known
-- event locations (stadium, river-trail bridge, entertainment district)?
-- This grounds the Q2 event-partnership recommendation in real usage, not
-- assumption.
-- Metric: Top stations per rider segment, ranked by share of that
-- segment's trips
-- ********************************************************

WITH station_crosswalk AS (
  SELECT * FROM UNNEST([
    STRUCT(4938 AS rentals_station_id, 11   AS station_info_id),
    STRUCT(7125 AS rentals_station_id, 111  AS station_info_id),
    STRUCT(7188 AS rentals_station_id, 3792 AS station_info_id),
    STRUCT(7131 AS rentals_station_id, 1111 AS station_info_id),
    STRUCT(7190 AS rentals_station_id, 2545 AS station_info_id),
    STRUCT(7187 AS rentals_station_id, 0    AS station_info_id)
  ])
),

deduplicated_rentals AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY start_time ASC) AS row_num
  FROM `bqproj26.zen_city.rentals`
),

cleaned_rentals AS (
  SELECT
    d.trip_id,
    CASE
      WHEN d.subscriber_type IN ('Student Membership', 'U.T. Student Membership')
        THEN 'Student Membership'
      ELSE d.subscriber_type
    END AS subscriber_type,
    COALESCE(cs_start.station_info_id, d.start_station_id) AS start_station_id,
    COALESCE(cs_end.station_info_id, d.end_station_id) AS end_station_id,
    d.duration_minutes
  FROM deduplicated_rentals d
  LEFT JOIN station_crosswalk cs_start ON d.start_station_id = cs_start.rentals_station_id
  LEFT JOIN station_crosswalk cs_end ON d.end_station_id = cs_end.rentals_station_id
  WHERE d.row_num = 1
    AND d.start_station_id IS NOT NULL
    AND d.end_station_id IS NOT NULL
    AND d.duration_minutes <= 1440
),

segmented AS (
  SELECT
    *,
    CASE
      WHEN subscriber_type = 'Student Membership' THEN 'Student'
      WHEN subscriber_type IN ('Local31', 'Local365', 'Annual Membership', 'HT Ram Membership')
        THEN 'Other Members'
      WHEN subscriber_type IN ('Pay-as-you-ride', 'Explorer', '3-Day Weekender',
                                '24 Hour Walk Up Pass', 'Single Trip (Pay-as-you-ride)')
        THEN 'Casual/Short-term'
      ELSE 'Other/Unclassified'
    END AS rider_segment
  FROM cleaned_rentals
),

segment_totals AS (
  SELECT rider_segment, COUNT(*) AS segment_trips
  FROM segmented
  GROUP BY rider_segment
),

station_counts AS (
  SELECT rider_segment, start_station_id, COUNT(*) AS trips_at_station
  FROM segmented
  GROUP BY rider_segment, start_station_id
),

ranked AS (
  SELECT
    sc.rider_segment,
    sc.start_station_id,
    sc.trips_at_station,
    ROW_NUMBER() OVER (PARTITION BY sc.rider_segment ORDER BY sc.trips_at_station DESC) AS station_rank
  FROM station_counts sc
)

SELECT
  r.rider_segment,
  r.station_rank,
  s.name AS station_name,
  r.trips_at_station,
  ROUND(r.trips_at_station * 100.0 / t.segment_trips, 1) AS pct_of_segment_trips
FROM ranked r
JOIN segment_totals t ON r.rider_segment = t.rider_segment
LEFT JOIN `bqproj26.zen_city.station_info` s ON r.start_station_id = s.station_id
WHERE r.station_rank <= 3
ORDER BY r.rider_segment, r.station_rank;


-- ********************************************************
-- PREDICTION METHOD: March-only Friday average (excluding Spring Break) +
-- one week of the consistent Q1 growth trend, projected to April 1st
-- ********************************************************

WITH station_crosswalk AS (
  SELECT * FROM UNNEST([
    STRUCT(4938 AS rentals_station_id, 11   AS station_info_id),
    STRUCT(7125 AS rentals_station_id, 111  AS station_info_id),
    STRUCT(7188 AS rentals_station_id, 3792 AS station_info_id),
    STRUCT(7131 AS rentals_station_id, 1111 AS station_info_id),
    STRUCT(7190 AS rentals_station_id, 2545 AS station_info_id),
    STRUCT(7187 AS rentals_station_id, 0    AS station_info_id)
  ])
),

deduplicated_rentals AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY start_time ASC) AS row_num
  FROM `bqproj26.zen_city.rentals`
),

cleaned_rentals AS (
  SELECT
    d.trip_id,
    CAST(d.start_time AS TIMESTAMP) AS start_time,
    COALESCE(cs_start.station_info_id, d.start_station_id) AS start_station_id,
    COALESCE(cs_end.station_info_id, d.end_station_id) AS end_station_id,
    d.duration_minutes
  FROM deduplicated_rentals d
  LEFT JOIN station_crosswalk cs_start ON d.start_station_id = cs_start.rentals_station_id
  LEFT JOIN station_crosswalk cs_end ON d.end_station_id = cs_end.rentals_station_id
  WHERE d.row_num = 1
    AND d.start_station_id IS NOT NULL
    AND d.end_station_id IS NOT NULL
    AND d.duration_minutes <= 1440
),

calendar_fridays AS (
  -- All 12 Fridays in Q1 2022, minus the Spring Break Friday
  SELECT date AS rental_date
  FROM UNNEST(GENERATE_DATE_ARRAY('2022-01-01', '2022-03-31')) AS date
  WHERE EXTRACT(DAYOFWEEK FROM date) = 6
    AND date != '2022-03-18'
),

station_2498_daily AS (
  SELECT EXTRACT(DATE FROM start_time) AS rental_date, COUNT(*) AS total_daily_rentals
  FROM cleaned_rentals
  WHERE start_station_id = 2498
  GROUP BY rental_date
),

friday_series AS (
  -- All 11 usable Fridays, in order, with a week index for the trend line
  SELECT
    cf.rental_date,
    COALESCE(s.total_daily_rentals, 0) AS total_daily_rentals,
    ROW_NUMBER() OVER (ORDER BY cf.rental_date) AS week_index
  FROM calendar_fridays cf
  LEFT JOIN station_2498_daily s ON cf.rental_date = s.rental_date
),

regression AS (
  -- Standard least-squares slope over the 11-point series (already
  -- verified: slope ~5.01/week, matches the earlier regression check)
  SELECT
    (COUNT(*) * SUM(week_index * total_daily_rentals) - SUM(week_index) * SUM(total_daily_rentals))
      / (COUNT(*) * SUM(week_index * week_index) - POW(SUM(week_index), 2)) AS weekly_growth
  FROM friday_series
),

march_only AS (
  -- Just the March Fridays (excluding Spring Break): the "current level"
  SELECT AVG(total_daily_rentals) AS march_friday_avg
  FROM friday_series
  WHERE EXTRACT(MONTH FROM rental_date) = 3
)

SELECT
  ROUND(m.march_friday_avg, 2) AS march_friday_avg,
  ROUND(r.weekly_growth, 2) AS weekly_growth,
  -- April 1st is exactly one week after the last used Friday (March 25)
  ROUND(m.march_friday_avg + r.weekly_growth, 0) AS predicted_april_1st_rentals
FROM march_only m, regression r;


