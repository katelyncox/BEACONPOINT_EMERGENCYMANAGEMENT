# Beacon Point EMA: Continuous Improvement with Posit Team

A worked example of a continuous improvement workflow for an emergency management agency, built entirely with open-source R and published with Posit Team. **Beacon Point Emergency Management Agency is fictional, and every record in this project is synthetic.**

The Continuous Improvement Office at Beacon Point surveys every staff member after a disaster deployment and records strengths and areas for improvement in after-action reports (AARs). This project shows how that work can run end to end without exports or a proprietary survey license:

1. **Collect** survey responses with an open-source survey built in R ([surveydown](https://surveydown.org))
2. **Analyze** ratings and open-text comments with transparent, repeatable methods (tidyverse, tidytext, topic models)
3. **Share** results as a weekly R Markdown brief that Posit Connect renders on a schedule and emails as HTML and PDF
4. **Explore** results in an interactive Shiny dashboard available only to designated users
5. **Teach** survey and interview design with an interactive learnr module
6. **Connect** to Azure Databricks, Dataverse, SharePoint and NVivo

## Project structure

```
BeaconPoint_EmergencyManagement/
├── app.R                      # Shiny dashboard: ratings, comment themes, similar-AAR search
├── ci-weekly-brief.Rmd        # Parameterized weekly brief (HTML + PDF), for scheduling on Connect
├── eda.Rmd                    # Full exploratory analysis (R Markdown)
├── survey/
│   ├── survey.qmd             # Survey questions (Markdown + R; see note below)
│   └── app.R                  # Runs the survey as a Shiny app and stores responses
├── R/ci_data.R                # Shared data loading, survey sync and chart styling
├── data/generate_data.R       # Creates the synthetic data (files start with "synthetic-")
├── ml/
│   ├── train_model.R          # Topic model + similarity index for open text
│   └── model_utils.R          # Text-analysis helpers
├── tutorials/mixed-methods-101/  # learnr interactive training module
├── databricks/
│   ├── databricks_ddl.sql     # Schema, tables, COPY INTO and a row filter
│   ├── upload_to_databricks.py  # Uploads the synthetic data (Python, uv)
│   └── databricks_examples.R  # Read from and write to Databricks from R
├── integrations/microsoft_and_nvivo.R  # NVivo export, Dataverse and SharePoint patterns
├── deploy.R                   # Publish each piece to Posit Connect
├── _brand.yml                 # Colors and fonts for every app and report
├── _dependencies.R            # Packages loaded indirectly, so renv records them
└── renv.lock                  # Exact package versions
```

## Setup

You need R 4.4 or later and RStudio, Positron or another IDE on Posit Workbench.

```r
# 1. Install the exact package versions used by this project
renv::restore()

# 2. Create the synthetic data. Optional: every script does this
#    automatically if the data is missing.
source("data/generate_data.R")

# 3. Train the text model. Optional: also automatic if missing.
source("ml/train_model.R")
```

The synthetic data isn't stored in version control. `data/generate_data.R` uses a fixed seed, so it produces identical files every time.

## Running each component

| Component | Command | What you'll see |
|---|---|---|
| Survey | `shiny::runApp("survey")` | A five-page post-deployment survey. Responses save to `survey/local_data.csv` |
| Dashboard | `shiny::runApp()` | Ratings, comment themes and a "find similar AAR observations" search. Click **Load new survey responses** to pull in new survey answers |
| Weekly brief | `rmarkdown::render("ci-weekly-brief.Rmd", params = list(region = "Gulf Coast"))` | An HTML brief, plus a PDF copy if LaTeX is installed (`tinytex::install_tinytex()`) |
| Analysis | `rmarkdown::render("eda.Rmd")` | The full exploratory analysis |
| Training module | Open `tutorials/mixed-methods-101/mixed-methods-101.Rmd` and click **Run Document** | Quizzes and R exercises on survey and interview design |
| NVivo export | `source("integrations/microsoft_and_nvivo.R")` | `integrations/exports/synthetic-nvivo-comments.csv`, ready to import into NVivo |

**About `survey.qmd`:** surveydown uses Quarto behind the scenes, so the survey file ends in `.qmd`. Its contents are ordinary Markdown and R code chunks, the same as R Markdown, and you don't need to know Quarto to edit it. Quarto ships with RStudio and Posit Workbench.

## Publishing to Posit Connect

`deploy.R` has one function per component. Run `deploy_dashboard()`, `deploy_weekly_brief()` and so on, or use the blue **Publish** button in RStudio. After publishing:

- **Weekly brief:** in the **Input** panel, choose a region and save it as a variant. Under **Schedule**, run it weekly (for example Mondays at 7:00 AM). Under **Email**, choose "send email after update" and add subscribers. Each email has a custom subject line and the PDF attached, and it's skipped in weeks with no new responses.
- **Dashboard:** under **Access**, choose "Specific users or groups."
- **Survey:** for production, switch `survey.qmd` to `mode: database`, run `surveydown::sd_db_config()` to set up PostgreSQL, and enter the same settings as environment variables in the content's **Vars** panel. Credentials never go in code.

## Working with Databricks

1. Generate the data, then load it: `cd databricks && uv run upload_to_databricks.py --warehouse-id <id> --profile workbench`
2. On Posit Workbench with Databricks managed credentials, step through `databricks/databricks_examples.R`. The Databricks ODBC driver must be installed on the server; check with `odbc::odbcListDrivers()`.
3. To switch the dashboard and reports to Databricks, add `CI_DATA_SOURCE=databricks` and `DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/<warehouse-id>` to `.Renviron` and restart R. If Databricks can't be reached, they fall back to the local database. The dashboard sidebar shows which source is in use.

No Databricks R cluster is needed. R runs on Posit Workbench or Connect, and `dplyr` code is translated to SQL that runs in the Databricks SQL warehouse.

## Custom branding with `_brand.yml`

Every app and report gets its colors and fonts from `_brand.yml`. No colors are set in the app or report code. To apply your own branding, edit the palette and fonts in that one file, and the dashboard, the weekly brief and the analysis all update. See the [brand.yml documentation](https://posit-dev.github.io/brand-yml/).

## Using this project as a starting point

- Swap `survey/survey.qmd` for your own questions. Each question is one `sd_question()` call.
- Point `load_ci_data()` in `R/ci_data.R` at your own database or Databricks tables. Every app and report reads through it.
- Replace the theme keywords in `ml/model_utils.R` with your own vocabulary. Rerun `ml/train_model.R` and review the proposed topic names before using them.
- Copy the parameter, email and PDF pattern in `ci-weekly-brief.Rmd` for any recurring report.

## Important Disclaimer

**This project contains synthetic data and analysis created for demonstration purposes only.**

All data, insights, business scenarios, and analytics presented in this demonstration project have been artificially generated using AI. The data does not represent actual business information, performance metrics, customer data, or operational statistics.

### Key Points:

- **Synthetic Data**: All datasets are computer-generated and designed to illustrate analytical capabilities
- **Illustrative Analysis**: Insights and recommendations are examples of the types of analysis possible with Posit tools
- **No Actual Business Data**: No real business information or data was used or accessed in creating this demonstration
- **Educational Purpose**: This project serves as a technical demonstration of data science workflows and reporting capabilities
- **AI-Generated Content**: Analysis, commentary, and business scenarios were created by AI for illustration purposes
- **No Real-World Implications**: The scenarios and insights presented should not be interpreted as actual business advice or strategies

This demonstration showcases how Posit's data science platform and open-source tools can be applied to the emergency management industry. The synthetic data and analysis provide a foundation for understanding the potential value of implementing similar analytical workflows with actual business data.

For questions about adapting these techniques to your real business scenarios, please contact your Posit representative.
---

*This demonstration was created using Posit's commercial data science tools and open-source packages. All synthetic data and analysis are provided for evaluation purposes only.*
