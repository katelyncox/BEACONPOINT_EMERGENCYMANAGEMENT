# ---------------------------------------------------------------------------
# Beacon Point EMA - publish the demo to Posit Connect
#
# This project contains synthetic data and analysis created for demonstration
# purposes only.
#
# Run the lines you need, one at a time, from the project root. The first
# time, connect RStudio to your server (Tools > Global Options > Publishing)
# or run rsconnect::connectUser(server = "connect.example.gov").
#
# The RStudio blue "Publish" button does the same thing; this script just
# pins the file lists so every deploy includes the shared helpers and data.
# ---------------------------------------------------------------------------

library(rsconnect)

source("R/ci_data.R")
ensure_data() # the synthetic data is not in git; create it before bundling
if (!file.exists("ml/text_model.rds")) source("ml/train_model.R", local = new.env())

# Files every root-level piece of content needs
shared_files <- c(
  "_brand.yml",
  "_dependencies.R",
  "renv.lock",
  "R/ci_data.R",
  "ml/model_utils.R",
  "ml/train_model.R",
  "ml/text_model.rds",
  "data/generate_data.R",
  "data/synthetic-ci-warehouse.sqlite"
)

# 1. Dashboard (Shiny). After publishing, open Access and choose
#    "Specific users or groups".
deploy_dashboard <- function() {
  deployApp(
    appDir = ".", appPrimaryDoc = "app.R",
    appFiles = c("app.R", shared_files),
    appTitle = "Beacon Point EMA - Deployment Experience Dashboard"
  )
}

# 2. Weekly brief (parameterized R Markdown). After publishing: Input panel
#    -> pick a region -> Save as variant; Schedule -> weekly; Email -> subscribers.
#    The PDF attachment needs TinyTeX (or another LaTeX) on the Connect server.
deploy_weekly_brief <- function() {
  deployApp(
    appDir = ".", appPrimaryDoc = "ci-weekly-brief.Rmd",
    appFiles = c("ci-weekly-brief.Rmd", shared_files),
    appTitle = "Beacon Point EMA - Weekly Deployment Experience Brief"
  )
}

# 3. EDA report (R Markdown)
deploy_eda <- function() {
  deployApp(
    appDir = ".", appPrimaryDoc = "eda.Rmd",
    appFiles = c("eda.Rmd", shared_files),
    appTitle = "Beacon Point EMA - Deployment Experience Analysis"
  )
}

# 4. Survey (surveydown). On Connect, switch survey.qmd to `mode: database`
#    and set the Postgres settings as environment variables in the Vars
#    panel, because files written inside a deployed app are not shared with
#    other content.
deploy_survey <- function() {
  deployApp(appDir = "survey", appTitle = "Beacon Point EMA - Post-Deployment Survey")
}

# 5. learnr training module (self-contained folder)
deploy_tutorial <- function() {
  deployDoc(
    "tutorials/mixed-methods-101/mixed-methods-101.Rmd",
    appTitle = "Beacon Point EMA - Mixed Methods 101"
  )
}

# deploy_dashboard()
# deploy_weekly_brief()
# deploy_eda()
# deploy_survey()
# deploy_tutorial()
