-- =============================================================================
-- Clickstream Analytics — Amazon Redshift Schema (DDL)
-- STREAMING INGESTION ARCHITECTURE
-- =============================================================================
-- This schema uses Redshift Streaming Ingestion to pull data directly from
-- Kinesis Data Streams. This provides sub-second data availability without
-- requiring Firehose→Redshift JDBC delivery (which has network topology issues
-- with private Redshift).
--
-- ARCHITECTURE:
--   Kinesis Data Stream → External Schema → Streaming MV → Analytical MVs
--                                              ↓
--                                         QuickSight
--
-- HOW TO RUN:
--   1. Wait for the Redshift Serverless workgroup to reach status AVAILABLE
--   2. Connect via Query Editor v2, select database: clickstream
--   3. Run this script top to bottom
--   4. Run: REFRESH MATERIALIZED VIEW clickstream.mv_clickstream_raw;
--      (This starts the streaming ingestion — data appears in seconds)
--
-- IMPORTANT: Replace <STREAMING_ROLE_ARN> and <KINESIS_STREAM_ARN> with actual
-- values from `terraform output`. The placeholders are:
--   - STREAMING_ROLE_ARN: terraform output redshift_streaming_role_arn
--   - KINESIS_STREAM_ARN: terraform output stream_arn
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS clickstream;

-- =============================================================================
-- STEP 1: External Schema for Kinesis Streaming Ingestion
-- =============================================================================
-- This creates a schema that references the Kinesis stream as a data source.
-- Redshift will pull data directly from Kinesis using the IAM role.
--
-- NOTE: The stream name in FROM KINESIS must match the Kinesis stream name
-- (without the full ARN), e.g., "clickstream-events"
-- =============================================================================

CREATE EXTERNAL SCHEMA IF NOT EXISTS kinesis_schema
FROM KINESIS
IAM_ROLE '<STREAMING_ROLE_ARN>';

-- =============================================================================
-- STEP 2: Streaming Materialized View (Landing Zone)
-- =============================================================================
-- This MV continuously ingests from Kinesis. It's the "landing table" for
-- real-time data. Once REFRESH is called, it starts consuming from the stream.
--
-- The kinesis_data column contains the raw JSON payload as a VARCHAR.
-- We parse it using JSON_EXTRACT_PATH_TEXT for each field.
-- =============================================================================

CREATE MATERIALIZED VIEW clickstream.mv_clickstream_raw
AUTO REFRESH YES
AS
SELECT
    -- Kinesis metadata
    approximate_arrival_timestamp,
    partition_key,
    shard_id,
    sequence_number,
    
    -- Parsed event fields (kinesis_data is VARBYTE, must cast to VARCHAR for JSON parsing)
    -- NOTE: TIMESTAMP conversion is NOT done here because AUTO REFRESH doesn't support
    -- mutable functions like CAST to TIMESTAMP. Convert in analytical MVs or at query time.
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'event_id')       AS event_id,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'timestamp')      AS event_timestamp_str,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'user_id')        AS user_id,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'session_id')     AS session_id,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'page_url')       AS page_url,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'page_category')  AS page_category,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'event_type')     AS event_type,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'referrer')       AS referrer,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'device')         AS device,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'browser')        AS browser,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'os')             AS os,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'country')        AS country,
    JSON_EXTRACT_PATH_TEXT(kinesis_data::VARCHAR, 'city')           AS city

FROM kinesis_schema."clickstream-events"

-- Filter to only valid JSON (defensive against malformed records)
WHERE CAN_JSON_PARSE(kinesis_data::VARCHAR);

-- =============================================================================
-- STEP 3: Analytical Materialized Views
-- =============================================================================
-- These views aggregate data from the streaming MV for dashboard use.
-- They need to be refreshed periodically (or use AUTO REFRESH if supported).
-- =============================================================================

-- Events per minute (for time-series chart)
-- Convert event_timestamp_str to TIMESTAMP here since streaming MV can't do it
CREATE MATERIALIZED VIEW clickstream.mv_events_per_minute AS
SELECT
    DATE_TRUNC('minute', CAST(REPLACE(event_timestamp_str, 'Z', '') AS TIMESTAMP)) AS minute,
    COUNT(*)                              AS event_count,
    COUNT(DISTINCT user_id)               AS distinct_users,
    COUNT(DISTINCT session_id)            AS distinct_sessions
FROM clickstream.mv_clickstream_raw
WHERE CAST(REPLACE(event_timestamp_str, 'Z', '') AS TIMESTAMP) >= DATEADD(hour, -24, GETDATE())
GROUP BY DATE_TRUNC('minute', CAST(REPLACE(event_timestamp_str, 'Z', '') AS TIMESTAMP));

-- Events by device (for pie chart)
CREATE MATERIALIZED VIEW clickstream.mv_events_by_device AS
SELECT
    device,
    COUNT(*)                AS event_count,
    COUNT(DISTINCT user_id) AS distinct_users
FROM clickstream.mv_clickstream_raw
WHERE CAST(REPLACE(event_timestamp_str, 'Z', '') AS TIMESTAMP) >= DATEADD(hour, -24, GETDATE())
GROUP BY device;

-- Events by country (for map visualization)
CREATE MATERIALIZED VIEW clickstream.mv_events_by_country AS
SELECT
    country,
    COUNT(*)                AS event_count,
    COUNT(DISTINCT user_id) AS distinct_users
FROM clickstream.mv_clickstream_raw
WHERE CAST(REPLACE(event_timestamp_str, 'Z', '') AS TIMESTAMP) >= DATEADD(hour, -24, GETDATE())
GROUP BY country;

-- Top pages (for bar chart)
-- NOTE: Redshift MVs don't support ORDER BY / LIMIT in definition.
-- Apply ranking at query time: SELECT * FROM ... ORDER BY view_count DESC LIMIT 20
CREATE MATERIALIZED VIEW clickstream.mv_top_pages AS
SELECT
    page_url,
    page_category,
    COUNT(*) AS view_count
FROM clickstream.mv_clickstream_raw
WHERE CAST(REPLACE(event_timestamp_str, 'Z', '') AS TIMESTAMP) >= DATEADD(hour, -1, GETDATE())
GROUP BY page_url, page_category;

-- =============================================================================
-- STEP 4: START STREAMING INGESTION
-- =============================================================================
-- Run this command to start the streaming ingestion process.
-- After this, data will appear in mv_clickstream_raw within seconds of
-- being written to Kinesis.
-- =============================================================================

-- REFRESH MATERIALIZED VIEW clickstream.mv_clickstream_raw;

-- =============================================================================
-- REFRESH COMMANDS FOR ANALYTICAL MVs
-- =============================================================================
-- Run these periodically to update the analytical views with fresh data.
-- The streaming MV (mv_clickstream_raw) auto-refreshes; these don't.
--
-- REFRESH MATERIALIZED VIEW clickstream.mv_events_per_minute;
-- REFRESH MATERIALIZED VIEW clickstream.mv_events_by_device;
-- REFRESH MATERIALIZED VIEW clickstream.mv_events_by_country;
-- REFRESH MATERIALIZED VIEW clickstream.mv_top_pages;
-- =============================================================================

-- =============================================================================
-- USEFUL QUERIES FOR VERIFICATION
-- =============================================================================
-- Check streaming MV status:
--   SELECT * FROM SVV_MV_REFRESH_STATUS WHERE mv_name = 'mv_clickstream_raw';
--
-- Count records in streaming MV:
--   SELECT COUNT(*) FROM clickstream.mv_clickstream_raw;
--
-- Sample recent events:
--   SELECT * FROM clickstream.mv_clickstream_raw 
--   ORDER BY approximate_arrival_timestamp DESC LIMIT 10;
--
-- Check ingestion lag (difference between event time and arrival time):
--   SELECT 
--     AVG(DATEDIFF(ms, event_timestamp, approximate_arrival_timestamp)) AS avg_lag_ms,
--     MAX(DATEDIFF(ms, event_timestamp, approximate_arrival_timestamp)) AS max_lag_ms
--   FROM clickstream.mv_clickstream_raw
--   WHERE approximate_arrival_timestamp > DATEADD(minute, -5, GETDATE());
-- =============================================================================
