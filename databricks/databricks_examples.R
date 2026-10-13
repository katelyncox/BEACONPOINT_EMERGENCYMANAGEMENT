# ---------------------------------------------------------------------------
# Beacon Point EMA - reading from and writing to Databricks from R
#
# This project contains synthetic data and analysis created for demonstration
# purposes only.
#
# Run these lines one at a time, from the project root, in a Workbench session with
# Databricks managed credentials. No token or password appears in this file:
# Workbench signs in to Databricks as you. Load the tables first with
# databricks/upload_to_databricks.py.
#
# No Databricks R cluster is needed. R runs in Workbench (or Connect), and the
# SQL warehouse does the heavy lifting.
# ---------------------------------------------------------------------------

library(DBI)
library(dplyr)
library(dbplyr)

# --- 1. Connect --------------------------------------------------------------
# Workbench supplies the workspace URL and your credentials. Only the SQL
# warehouse's HTTP path is needed (Databricks: SQL Warehouses > Connection details).
con <- dbConnect(
  odbc::databricks(),
  httpPath = Sys.getenv("DATABRICKS_HTTP_PATH", "/sql/1.0/warehouses/<warehouse-id>")
)

# On Posit Connect, add a Databricks OAuth integration to the content and
# load connectcreds. The same dbConnect() call then runs as the *viewer*,
# so Databricks permissions and row filters apply per person.
# library(connectcreds)

# --- 2. Read: dplyr code that runs inside Databricks --------------------------
responses <- tbl(con, I("sol_eng_demo_nickp.beacon_point_ci.survey_responses"))

by_region <- responses |>
  group_by(region) |>
  summarise(
    responses = n(),
    avg_overall = mean(score_overall, na.rm = TRUE),
    avg_logistics = mean(score_logistics, na.rm = TRUE)
  ) |>
  arrange(avg_overall)

show_query(by_region) # the SQL that dplyr wrote for you
by_region |> collect() # only the small summary comes back to R

# Signed in as demo_databricks_user@posit.co? The row filter in
# databricks_ddl.sql limits you to Gulf Coast and Eastern Seaboard, with no
# filtering code in R.

# --- 3. Write back: Posit as a light persistence bridge ------------------------
# Results computed in R (or responses collected by the surveydown survey) can
# be saved to Databricks so other tools, such as Power BI or Genie, can use them.
source("R/ci_data.R")
ci <- load_ci_data()

weekly_summary <- ci$responses |>
  mutate(week = as.Date(cut(submitted_at, "week"))) |>
  group_by(week, region) |>
  summarise(responses = n(), avg_overall = mean(score_overall), .groups = "drop")

dbWriteTable(
  con,
  Id(catalog = "sol_eng_demo_nickp", schema = "beacon_point_ci", table = "weekly_summary"),
  weekly_summary,
  overwrite = TRUE
)

tbl(con, I("sol_eng_demo_nickp.beacon_point_ci.weekly_summary")) |> head()

# For larger uploads, write a CSV to a Unity Catalog volume and load it with
# COPY INTO, the same pattern databricks/upload_to_databricks.py uses.

dbDisconnect(con)
