# ---------------------------------------------------------------------------
# Beacon Point EMA - Microsoft Dataverse, SharePoint and NVivo patterns
#
# This project contains synthetic data and analysis created for demonstration
# purposes only.
#
# Section 1 runs as is and writes a file NVivo can import. Sections 2 and 3
# are commented patterns to adapt once your IT team confirms the connection
# details and which packages are approved.
#
# Run from the project root:  source("integrations/microsoft_and_nvivo.R")
# ---------------------------------------------------------------------------

source("R/ci_data.R")
ci <- load_ci_data()

# --- 1. NVivo: export open-text responses for qualitative coding -------------
# NVivo imports a spreadsheet as a "dataset": one row per case, with text
# columns to code and classification columns (attributes) to compare cases.
# There is no direct R-to-NVivo connector; a CSV or Excel file is the
# standard hand-off. Coded results can be exported from NVivo and read back
# into R with readr or readxl.

dir.create(ci_path("integrations", "exports"), showWarnings = FALSE)

nvivo_export <- ci$responses |>
  filter(!is.na(comment)) |>
  transmute(
    case_id = response_id,
    submitted = submitted_at,
    region, incident_type, role, first_deployment,
    overall_rating = score_overall,
    would_redeploy,
    comment
  )

export_path <- ci_path("integrations", "exports", "synthetic-nvivo-comments.csv")
write_csv(nvivo_export, export_path)
message("Wrote ", nrow(nvivo_export), " comments for NVivo to ", export_path)
# For an .xlsx file instead (if approved): writexl::write_xlsx(nvivo_export, "....xlsx")

# --- 2. Microsoft Dataverse --------------------------------------------------
# Option A: the read-only SQL (TDS) endpoint, over ODBC with Microsoft Entra ID
# sign-in. Requires the Microsoft ODBC Driver for SQL Server on Workbench.
#
# dv <- DBI::dbConnect(
#   odbc::odbc(),
#   Driver = "ODBC Driver 18 for SQL Server",
#   Server = "<your-org>.crm.dynamics.com,5558",
#   Database = "<your-org>",
#   Authentication = "ActiveDirectoryInteractive",
#   UID = "<you>@<agency>.gov"
# )
# programs <- dplyr::tbl(dv, "<table_logical_name>") |> dplyr::collect()
#
# Option B: the Dataverse Web API (OData) with httr2, for reads and writes.
#
# req <- httr2::request("https://<your-org>.crm.dynamics.com/api/data/v9.2/<entity_set>") |>
#   httr2::req_auth_bearer_token(Sys.getenv("DATAVERSE_TOKEN")) |>
#   httr2::req_url_query(`$select` = "name,createdon", `$top` = 100)
# programs <- httr2::req_perform(req) |> httr2::resp_body_json()
#
# Option C: sync Dataverse into Databricks (Dataverse link / export) and read
# it alongside the survey data with odbc::databricks(). See databricks/.

# --- 3. SharePoint and Power Platform ---------------------------------------
# Microsoft365R reads and writes SharePoint and OneDrive files with Entra ID
# sign-in.
#
# site <- Microsoft365R::get_sharepoint_site(site_url = "https://<agency>.sharepoint.com/sites/<site>")
# drive <- site$get_drive()
# drive$upload_file(export_path, "Continuous Improvement/synthetic-nvivo-comments.csv")
# survey_export <- drive$download_file("Surveys/latest-export.xlsx", dest = tempfile(fileext = ".xlsx"))
#
# Power BI and Power Automate can use content published on Posit Connect:
#   - a CSV or pinned dataset on Connect, read by URL with a Connect API key
#   - a Plumber API on Connect, called by a Power Automate HTTP action
#   - the Connect Server API, e.g. to re-run a report after a flow finishes
