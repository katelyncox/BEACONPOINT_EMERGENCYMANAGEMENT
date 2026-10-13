-- ---------------------------------------------------------------------------
-- Beacon Point EMA - Databricks objects for the Continuous Improvement demo
--
-- This project contains synthetic data and analysis created for demonstration
-- purposes only. Beacon Point Emergency Management Agency is fictional.
--
-- Run by databricks/upload_to_databricks.py, which first uploads the CSV files
-- to the volume below. Statements are separated by semicolons.
-- ---------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS sol_eng_demo_nickp.beacon_point_ci
  COMMENT 'SYNTHETIC demo data for a fictional emergency management agency (Posit demo)';

CREATE VOLUME IF NOT EXISTS sol_eng_demo_nickp.beacon_point_ci.raw_files
  COMMENT 'Landing zone for synthetic CSV uploads';

-- --- Tables ------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sol_eng_demo_nickp.beacon_point_ci.incidents (
  incident_id STRING,
  incident_name STRING,
  incident_type STRING,
  region STRING,
  start_date DATE,
  duration_days INT,
  staff_deployed INT,
  households_affected INT
) COMMENT 'SYNTHETIC: fictional disaster deployments';

CREATE TABLE IF NOT EXISTS sol_eng_demo_nickp.beacon_point_ci.survey_responses (
  response_id STRING,
  submitted_at DATE,
  incident_id STRING,
  region STRING,
  incident_type STRING,
  role STRING,
  first_deployment STRING,
  deployment_weeks DOUBLE,
  score_onboarding INT,
  score_tools_tech INT,
  score_communication INT,
  score_logistics INT,
  score_leadership INT,
  score_overall INT,
  would_redeploy STRING,
  comment STRING
) COMMENT 'SYNTHETIC: post-deployment experience survey responses';

CREATE TABLE IF NOT EXISTS sol_eng_demo_nickp.beacon_point_ci.aar_observations (
  aar_id STRING,
  incident_id STRING,
  incident_name STRING,
  incident_type STRING,
  region STRING,
  report_date DATE,
  core_capability STRING,
  section STRING,
  observation STRING,
  recommendation STRING
) COMMENT 'SYNTHETIC: after-action report strengths and areas for improvement';

-- --- Load from the volume ----------------------------------------------------
-- The CSVs start with "#" comment lines that mark them as synthetic, so the
-- `comment` option skips them. COPY INTO is idempotent: re-running it skips
-- files that were already loaded.

COPY INTO sol_eng_demo_nickp.beacon_point_ci.incidents
  FROM '/Volumes/sol_eng_demo_nickp/beacon_point_ci/raw_files/synthetic-incidents.csv'
  FILEFORMAT = CSV
  FORMAT_OPTIONS ('header' = 'true', 'comment' = '#', 'inferSchema' = 'true')
  COPY_OPTIONS ('mergeSchema' = 'false');

COPY INTO sol_eng_demo_nickp.beacon_point_ci.survey_responses
  FROM '/Volumes/sol_eng_demo_nickp/beacon_point_ci/raw_files/synthetic-survey-responses.csv'
  FILEFORMAT = CSV
  FORMAT_OPTIONS ('header' = 'true', 'comment' = '#', 'inferSchema' = 'true', 'multiLine' = 'true', 'escape' = '"')
  COPY_OPTIONS ('mergeSchema' = 'false');

COPY INTO sol_eng_demo_nickp.beacon_point_ci.aar_observations
  FROM '/Volumes/sol_eng_demo_nickp/beacon_point_ci/raw_files/synthetic-aar-observations.csv'
  FILEFORMAT = CSV
  FORMAT_OPTIONS ('header' = 'true', 'comment' = '#', 'inferSchema' = 'true', 'multiLine' = 'true', 'escape' = '"')
  COPY_OPTIONS ('mergeSchema' = 'false');

-- --- Row filter (governance demo) --------------------------------------------
-- The demo account demo_databricks_user@posit.co sees only Gulf Coast and
-- Eastern Seaboard rows. Everyone else sees all rows. The same Shiny app or
-- report therefore shows different numbers depending on who is signed in,
-- with no filtering code in R.

CREATE OR REPLACE FUNCTION sol_eng_demo_nickp.beacon_point_ci.region_filter(region STRING)
  RETURNS BOOLEAN
  RETURN IF(
    current_user() = 'demo_databricks_user@posit.co',
    region IN ('Gulf Coast', 'Eastern Seaboard'),
    TRUE
  );

ALTER TABLE sol_eng_demo_nickp.beacon_point_ci.survey_responses
  SET ROW FILTER sol_eng_demo_nickp.beacon_point_ci.region_filter ON (region);

ALTER TABLE sol_eng_demo_nickp.beacon_point_ci.aar_observations
  SET ROW FILTER sol_eng_demo_nickp.beacon_point_ci.region_filter ON (region);

ALTER TABLE sol_eng_demo_nickp.beacon_point_ci.incidents
  SET ROW FILTER sol_eng_demo_nickp.beacon_point_ci.region_filter ON (region);
