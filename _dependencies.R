# ---------------------------------------------------------------------------
# Packages this project needs that no script loads directly. This file is
# never run; it exists so renv::snapshot() records these in renv.lock and
# Posit Connect installs them when the content is published.
# ---------------------------------------------------------------------------

library(brand.yml)    # bslib reads _brand.yml with it (app and reports)
library(reshape2)     # tidytext uses it to tidy the LDA topic model
library(connectcreds) # Databricks viewer credentials on Connect (app.R, databricks/)
library(odbc)         # odbc::databricks() connections (databricks/, commented code)
