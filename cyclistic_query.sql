-- ============================================================
-- Project      : Cyclistic Bikeshare Dashboard
-- Query        : Trip Analysis & Geographic Enrichment
-- Author       : Moh Rohman Abdilah
-- Tool         : Google BigQuery (Standard SQL)
-- ============================================================
-- Description  :
--   This query extracts and transforms NYC Citi Bike trip data
--   (2014-2015, displayed as 2019-2020) by joining it with
--   geographic boundaries, neighborhood references, and daily
--   weather data to produce a single analysis-ready flat table
--   for Tableau dashboard development.
--
-- Data Sources :
--   1. bigquery-public-data.new_york_citibike.citibike_trips
--      → Primary trip data (start/end time, duration, user type)
--   2. bigquery-public-data.geo_us_boundaries.zip_codes
--      → ZIP code polygons for geographic mapping
--   3. bigquery-public-data.noaa_gsod.gsod20*
--      → Daily weather data from Central Park station
--   4. valid-cedar-491205-s0.cyclistic.zip_codes (custom upload)
--      → NYC neighborhood reference table (zip, borough, neighborhood)
--
-- Output       : 14 columns, grouped by all dimensions
-- ============================================================


SELECT

  -- User type: 'Customer' (single-use) or 'Subscriber' (member)
  TRI.usertype,

  -- Geographic info for the starting station
  ZIPSTART.zip_code                 AS zip_code_start,
  ZIPSTARTNAME.borough              AS borough_start,
  ZIPSTARTNAME.neighborhood         AS neighborhood_start,

  -- Geographic info for the ending station
  ZIPEND.zip_code                   AS zip_code_end,
  ZIPENDNAME.borough                AS borough_end,
  ZIPENDNAME.neighborhood           AS neighborhood_end,

  -- Trip dates shifted +5 years (2014-2015 → 2019-2020)
  -- to make the dashboard appear more recent
  DATE_ADD(DATE(TRI.starttime), INTERVAL 5 YEAR)  AS start_day,
  DATE_ADD(DATE(TRI.stoptime),  INTERVAL 5 YEAR)  AS stop_day,

  -- Daily weather metrics from NOAA Central Park station
  WEA.temp    AS day_mean_temperature,    -- Mean temperature (°F)
  WEA.wdsp    AS day_mean_wind_speed,     -- Mean wind speed (knots)
  WEA.prcp    AS day_total_precipitation, -- Total precipitation (inches)

  -- Trip duration converted from seconds to minutes,
  -- rounded to the nearest 10 minutes to reduce row count
  ROUND(CAST(TRI.tripduration / 60 AS INT64), -1) AS trip_minutes,

  -- Total number of trips per group
  COUNT(TRI.bikeid) AS trip_count


FROM
  `bigquery-public-data.new_york_citibike.citibike_trips` AS TRI


-- JOIN 1: Map start station coordinates to a ZIP code polygon
-- Uses ST_WITHIN + ST_GEOGPOINT to perform a spatial point-in-polygon lookup
INNER JOIN
  `bigquery-public-data.geo_us_boundaries.zip_codes` AS ZIPSTART
  ON ST_WITHIN(
    ST_GEOGPOINT(TRI.start_station_longitude, TRI.start_station_latitude),
    ZIPSTART.zip_code_geom
  )

-- JOIN 2: Map end station coordinates to a ZIP code polygon
-- Same spatial logic applied to the ending station
INNER JOIN
  `bigquery-public-data.geo_us_boundaries.zip_codes` AS ZIPEND
  ON ST_WITHIN(
    ST_GEOGPOINT(TRI.end_station_longitude, TRI.end_station_latitude),
    ZIPEND.zip_code_geom
  )

-- JOIN 3: Enrich each trip with daily weather data
-- Matches trip date to NOAA weather station record using date parsing
INNER JOIN
  `bigquery-public-data.noaa_gsod.gsod20*` AS WEA
  ON PARSE_DATE("%Y%m%d", CONCAT(WEA.year, WEA.mo, WEA.da)) = DATE(TRI.starttime)

-- JOIN 4: Resolve start ZIP code to borough and neighborhood name
-- Uses custom-uploaded NYC neighborhood reference table
INNER JOIN
  `valid-cedar-491205-s0.cyclistic.zip_codes` AS ZIPSTARTNAME
  ON ZIPSTART.zip_code = CAST(ZIPSTARTNAME.zip AS STRING)

-- JOIN 5: Resolve end ZIP code to borough and neighborhood name
INNER JOIN
  `valid-cedar-491205-s0.cyclistic.zip_codes` AS ZIPENDNAME
  ON ZIPEND.zip_code = CAST(ZIPENDNAME.zip AS STRING)


WHERE
  -- Filter to Central Park weather station only (WBAN: 94728)
  WEA.wban = '94728'

  -- Filter to trip data from 2014 and 2015 only
  -- (displayed as 2019-2020 after DATE_ADD transformation)
  AND EXTRACT(YEAR FROM DATE(TRI.starttime)) BETWEEN 2014 AND 2015


-- Group by all non-aggregated columns (positions 1-13)
GROUP BY
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
