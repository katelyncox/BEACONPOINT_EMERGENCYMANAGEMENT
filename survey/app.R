# ---------------------------------------------------------------------------
# Beacon Point EMA - Post-Deployment Experience Survey (surveydown)
#
# This project contains synthetic data and analysis created for demonstration
# purposes only.
#
# An open-source alternative to a hosted survey tool. The survey content lives
# in survey.qmd; this file wires it to storage and runs it as a Shiny app, so
# it can be published to Posit Connect like any other Shiny app.
#
# Run locally:  shiny::runApp("survey")
# ---------------------------------------------------------------------------

library(surveydown)

# --- Storage ---------------------------------------------------------------
# The survey runs in `mode: local` (set in survey.qmd), which writes every
# completed response to survey/local_data.csv. The dashboard picks those rows
# up and loads them into the program database (see R/ci_data.R).
#
# For production, surveydown writes straight to PostgreSQL:
#   1. Run sd_db_config() once. It stores host, port, user and password in a
#      local .env file, which is git-ignored and never published.
#   2. On Posit Connect, set the same values as environment variables in the
#      content's "Vars" panel instead of shipping the .env file.
#   3. Change `mode: local` to `mode: database` in survey.qmd.

db <- sd_db_connect()

# --- UI and server ---------------------------------------------------------

ui <- sd_ui()

server <- function(input, output, session) {
  # Conditional logic goes here, e.g. sd_show_if() to show a follow-up
  # question only to first-time deployers. This survey keeps every question
  # visible so results compare cleanly over time.
  sd_server(db = db)
}

shiny::shinyApp(ui = ui, server = server)
