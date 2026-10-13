# ---------------------------------------------------------------------------
# Beacon Point EMA - shared data helpers
#
# This project contains synthetic data and analysis created for demonstration
# purposes only.
#
# Used by the dashboard (app.R), the EDA (eda.Rmd), the scheduled report
# (ci-weekly-brief.Rmd) and the learnr tutorial, so every product
# reads the same data the same way.
# ---------------------------------------------------------------------------

library(dplyr)
library(readr)
library(ggplot2)
library(DBI)

# --- Paths -----------------------------------------------------------------

# Find the project root (the folder holding _brand.yml) so code works the same
# whether it runs from the root or from a subfolder.
ci_root <- function(start = getwd()) {
  dir <- normalizePath(start)
  while (!file.exists(file.path(dir, "_brand.yml"))) {
    parent <- dirname(dir)
    if (parent == dir) stop("Could not find the project root (_brand.yml).")
    dir <- parent
  }
  dir
}

ci_path <- function(...) file.path(ci_root(), ...)

DB_PATH <- function() ci_path("data", "synthetic-ci-warehouse.sqlite")

# --- Survey dimensions -----------------------------------------------------

SCORE_LABELS <- c(
  score_onboarding    = "Onboarding & training",
  score_tools_tech    = "Tools & technology",
  score_communication = "Communication & briefings",
  score_logistics     = "Lodging & logistics",
  score_leadership    = "Leadership support",
  score_overall       = "Overall experience"
)

# --- Data access -----------------------------------------------------------

# Synthetic data is not checked into git. Generate it on first use.
ensure_data <- function() {
  if (!file.exists(DB_PATH())) {
    message("Synthetic data not found; running data/generate_data.R ...")
    owd <- setwd(ci_root())
    on.exit(setwd(owd))
    source("data/generate_data.R", local = new.env())
  }
  invisible(DB_PATH())
}

# Load completed responses from the surveydown survey (survey/local_data.csv)
# into the program database. surveydown stores the option *values* from
# survey.qmd (e.g. "pacific_rim"), so they are mapped back to display labels.
#
# With surveydown in `mode: database`, responses are already in Postgres and
# this step becomes a simple query of that table.
sync_survey_responses <- function(con, survey_csv = ci_path("survey", "local_data.csv")) {
  dbExecute(con, "DELETE FROM survey_responses WHERE source = 'Live survey'")
  if (!file.exists(survey_csv)) {
    return(invisible(0L))
  }

  live <- read_csv(survey_csv, col_types = cols(.default = col_character()))
  if (!"score_overall" %in% names(live)) {
    return(invisible(0L))
  }

  to_label <- function(x) tools::toTitleCase(gsub("_", " ", x))

  live <- live |>
    filter(!is.na(score_overall), score_overall != "") |>
    transmute(
      response_id = paste0("LIVE-", substr(session_id, 1, 8)),
      submitted_at = substr(time_start, 1, 10),
      incident_id = NA_character_,
      region = to_label(region),
      incident_type = to_label(incident_type),
      role = to_label(role),
      first_deployment = to_label(first_deployment),
      deployment_weeks = suppressWarnings(as.numeric(deployment_weeks)),
      across(starts_with("score_"), \(x) suppressWarnings(as.numeric(x))),
      would_redeploy = to_label(would_redeploy),
      comment = na_if(comment, ""),
      source = "Live survey"
    )

  if (nrow(live) > 0) dbAppendTable(con, "survey_responses", live)
  invisible(nrow(live))
}

# One call that every product uses to get analysis-ready tables.
load_ci_data <- function(sync_live = TRUE) {
  ensure_data()
  con <- dbConnect(RSQLite::SQLite(), DB_PATH())
  on.exit(dbDisconnect(con))

  # To read from Databricks instead, swap the connection above for
  #   con <- DBI::dbConnect(odbc::databricks(), httpPath = "<warehouse-http-path>")
  # and point the table names at the catalog, e.g.
  #   dplyr::tbl(con, I("sol_eng_demo_nickp.beacon_point_ci.survey_responses"))
  # See databricks/databricks_examples.R.

  if (sync_live) sync_survey_responses(con)

  list(
    responses = dbReadTable(con, "survey_responses") |>
      mutate(
        submitted_at = as.Date(submitted_at),
        quarter = paste0(format(submitted_at, "%Y"), " Q", (as.integer(format(submitted_at, "%m")) - 1) %/% 3 + 1)
      ),
    incidents = dbReadTable(con, "incidents") |>
      mutate(start_date = as.Date(start_date)),
    aar = dbReadTable(con, "aar_observations") |>
      mutate(report_date = as.Date(report_date))
  )
}

# --- Brand colors for charts -----------------------------------------------
# Chart colors come from _brand.yml so a rebrand is a one-file change.

brand_palette <- function() {
  yaml::read_yaml(ci_path("_brand.yml"))$color$palette
}

# Categorical series colors, always assigned in this fixed order
ci_series_colors <- function(n = 6) {
  p <- brand_palette()
  unname(unlist(p[c("blue", "orange", "aqua", "yellow", "magenta", "violet")]))[seq_len(n)]
}

# Diverging 5-point scale for Likert ratings: red (poor) - gray - blue (good)
likert_colors <- function() {
  c(
    "1" = "#C93A39", "2" = "#EE9A99", "3" = "#D3D1CB",
    "4" = "#86B6EF", "5" = "#1C5CAB"
  )
}

theme_ci <- function(base_size = 13) {
  p <- brand_palette()
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", color = p$navy),
      plot.subtitle = element_text(color = p$slate),
      plot.caption = element_text(color = p$slate, size = rel(0.75), hjust = 0),
      axis.text = element_text(color = p$slate),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "#ECEBE7", linewidth = 0.4),
      legend.position = "top",
      legend.justification = "left",
      plot.title.position = "plot",
      plot.caption.position = "plot"
    )
}

SYNTHETIC_CAPTION <- "Synthetic data generated for demonstration purposes only."
