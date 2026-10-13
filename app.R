# ---------------------------------------------------------------------------
# Beacon Point EMA - Deployment Experience Dashboard (Shiny)
#
# This project contains synthetic data and analysis created for demonstration
# purposes only.
#
# Reads the same program database as the EDA and the weekly brief, including
# any responses collected by the surveydown survey in survey/. Charts are
# static ggplot2 and tables are gt, so the app adds no JavaScript widget
# packages beyond Shiny and bslib themselves.
#
# Run locally:  shiny::runApp()
# On Posit Connect, limit access to designated users in the "Access" panel.
# ---------------------------------------------------------------------------

library(shiny)
library(bslib)
library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)
library(gt)

source("R/ci_data.R")
source("ml/model_utils.R")

# --- Databricks (optional) --------------------------------------------------
# With Workbench managed credentials, or a Connect OAuth integration, this app
# can read straight from Databricks instead of the local database. Viewers see
# only the rows their own Databricks identity is allowed to see.
#
# library(connectcreds)  # picks up the viewer's Connect OAuth credentials
# library(dbplyr)
#
# pool_con <- reactive({
#   con <- try(pool::dbPool(
#     odbc::databricks(),
#     httpPath = Sys.getenv("DATABRICKS_HTTP_PATH")
#   ))
#   validate(need(!inherits(con, "try-error"), "Issue connecting to Databricks"))
#   con
# })
#
# The filtering and averaging below can then run inside Databricks, e.g.
#   tbl(pool_con(), I("sol_eng_demo_nickp.beacon_point_ci.survey_responses")) |>
#     filter(region %in% !!input$region) |>
#     summarise(across(starts_with("score_"), mean)) |>
#     collect()

if (!file.exists(MODEL_PATH())) source("ml/train_model.R", local = new.env())
model <- readRDS(MODEL_PATH())

initial <- load_ci_data()
regions <- sort(unique(initial$responses$region))
hazards <- sort(unique(initial$responses$incident_type))
date_range <- range(initial$responses$submitted_at)

DISCLAIMER <- "This project contains synthetic data and analysis created for demonstration purposes only."

# --- UI --------------------------------------------------------------------

filters <- sidebar(
  width = 280,
  selectInput("region", "Region", regions, selected = regions, multiple = TRUE),
  selectInput("hazard", "Incident type", hazards, selected = hazards, multiple = TRUE),
  radioButtons(
    "first", "Deployment experience",
    c("Everyone" = "all", "First deployment" = "Yes", "Experienced" = "No"),
    inline = FALSE
  ),
  dateRangeInput(
    "dates", "Submitted between",
    start = date_range[1], end = date_range[2],
    min = date_range[1], max = Sys.Date()
  ),
  hr(),
  actionButton("refresh", "Load new survey responses", class = "btn-outline-primary"),
  textOutput("live_count", container = \(...) p(class = "small text-muted mt-2", ...))
)

overview_tab <- nav_panel(
  "Overview",
  div(class = "alert alert-secondary py-2 small mb-0", strong(DISCLAIMER),
      " Beacon Point Emergency Management Agency is fictional."),
  layout_column_wrap(
    width = 1 / 4, fill = FALSE,
    value_box("Survey responses", textOutput("n_responses"), theme = "primary"),
    value_box("Average overall rating", textOutput("avg_overall"), p("on a 1-5 scale")),
    value_box("Would deploy again", textOutput("pct_redeploy")),
    value_box("Written comments", textOutput("n_comments"))
  ),
  layout_columns(
    col_widths = c(6, 6),
    card(
      full_screen = TRUE,
      card_header("Average rating by area"),
      plotOutput("by_area")
    ),
    card(
      full_screen = TRUE,
      card_header("Overall experience by quarter"),
      plotOutput("trend")
    )
  )
)

themes_tab <- nav_panel(
  "Comments & themes",
  layout_columns(
    col_widths = c(5, 7),
    card(
      full_screen = TRUE,
      card_header("What people write about"),
      plotOutput("topics"),
      card_footer(class = "small text-muted",
        "Themes come from a topic model with a fixed seed (ml/train_model.R): ",
        "the same comment always gets the same theme.")
    ),
    card(
      full_screen = TRUE,
      card_header("Comments"),
      selectInput("theme_pick", NULL, c("All themes", model$topic_labels), width = "100%"),
      uiOutput("comments")
    )
  )
)

similar_tab <- nav_panel(
  "Find similar AAR observations",
  layout_columns(
    col_widths = c(4, 8),
    card(
      card_header("Describe a new issue"),
      textAreaInput(
        "query", NULL, rows = 5, width = "100%",
        value = "The night shift never got a handoff briefing and repeated the day team's work"
      ),
      actionButton("search", "Search past AARs", class = "btn-primary"),
      card_footer(class = "small text-muted",
        "Matches use word overlap weighted by how rare each word is (TF-IDF). ",
        "\"Matched on\" shows exactly which words drove each match. No generative AI.")
    ),
    card(
      full_screen = TRUE,
      card_header("Most similar past observations"),
      uiOutput("similar")
    )
  )
)

ui <- page_navbar(
  title = "Beacon Point EMA | Deployment Experience",
  theme = bs_theme(brand = "_brand.yml"),
  sidebar = filters,
  overview_tab,
  themes_tab,
  similar_tab,
  nav_spacer(),
  nav_item(span(class = "small text-white-50", "Synthetic data for demonstration only"))
)

# --- Server ----------------------------------------------------------------

server <- function(input, output, session) {
  ci <- reactiveVal(initial)

  # Pull in any responses submitted through the surveydown survey since the
  # app started. This is the "survey -> database -> app" step of the demo.
  observeEvent(input$refresh, {
    ci(load_ci_data())
    showNotification("Survey responses refreshed.", type = "message")
  })

  output$live_count <- renderText({
    n <- sum(ci()$responses$source == "Live survey")
    paste0(n, " response", if (n != 1) "s", " from the live survey")
  })

  filtered <- reactive({
    req(input$region, input$hazard, input$dates)
    r <- ci()$responses |>
      filter(
        region %in% input$region,
        incident_type %in% input$hazard,
        submitted_at >= input$dates[1], submitted_at <= input$dates[2]
      )
    if (input$first != "all") r <- filter(r, first_deployment == input$first)
    r
  })

  enough_data <- function() {
    validate(need(nrow(filtered()) > 0, "No responses match these filters."))
  }

  # --- Value boxes ---------------------------------------------------------

  output$n_responses <- renderText(comma(nrow(filtered())))
  output$avg_overall <- renderText({
    enough_data()
    number(mean(filtered()$score_overall, na.rm = TRUE), 0.01)
  })
  output$pct_redeploy <- renderText({
    enough_data()
    percent(mean(filtered()$would_redeploy == "Yes", na.rm = TRUE), 1)
  })
  output$n_comments <- renderText(comma(sum(!is.na(filtered()$comment))))

  # --- Charts --------------------------------------------------------------

  output$by_area <- renderPlot({
    enough_data()
    filtered() |>
      summarise(across(starts_with("score_") & !score_overall, \(x) mean(x, na.rm = TRUE))) |>
      pivot_longer(everything(), names_to = "dimension", values_to = "avg") |>
      mutate(label = reorder(SCORE_LABELS[dimension], avg)) |>
      ggplot(aes(avg, label)) +
      geom_col(width = 0.6, fill = ci_series_colors(1)) +
      geom_text(aes(label = number(avg, 0.1)), hjust = -0.2, size = 4.2, color = "#52514E") +
      scale_x_continuous(limits = c(0, 5.3), breaks = 1:5, expand = expansion(mult = 0)) +
      labs(x = "Average rating (1 = very poor, 5 = excellent)", y = NULL, caption = SYNTHETIC_CAPTION) +
      theme_ci(14) + theme(axis.title = element_text(size = rel(0.8), color = "#52514E")) +
      theme(panel.grid.major.y = element_blank())
  }, res = 96)

  output$trend <- renderPlot({
    enough_data()
    trend <- filtered() |>
      group_by(quarter) |>
      summarise(avg = mean(score_overall, na.rm = TRUE), n = n()) |>
      # The data ends mid-quarter, so mark the current quarter as partial
      mutate(quarter = if_else(quarter == max(quarter), paste(quarter, "(to date)"), quarter))
    ggplot(trend, aes(quarter, avg, group = 1)) +
      geom_line(linewidth = 1, color = ci_series_colors(1)) +
      geom_point(size = 3, color = "white") +
      geom_point(size = 2.2, color = ci_series_colors(1)) +
      geom_text(
        data = slice_tail(trend, n = 1), aes(label = number(avg, 0.1)),
        vjust = -1.1, size = 4.2, color = "#52514E"
      ) +
      scale_y_continuous(limits = c(1, 5), breaks = 1:5) +
      labs(x = NULL, y = "Average overall rating", caption = SYNTHETIC_CAPTION) +
      theme_ci(14) + theme(axis.title = element_text(size = rel(0.8), color = "#52514E")) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  }, res = 96)

  # --- Comments and themes -------------------------------------------------

  # Theme for every comment in the current filter. Training comments already
  # have a theme; new live-survey comments are scored with the saved model.
  comment_topics <- reactive({
    comments <- filtered() |>
      filter(!is.na(comment)) |>
      select(response_id, submitted_at, region, role, score_overall, comment)
    known <- inner_join(comments, select(model$doc_topics, doc_id, topic_label),
                        by = c("response_id" = "doc_id"))
    new <- anti_join(comments, model$doc_topics, by = c("response_id" = "doc_id"))
    if (nrow(new) > 0) {
      post <- assign_topics(model, new$comment)
      new$topic_label <- "Unclassified"
      if (!is.null(post)) {
        new$topic_label[as.integer(rownames(post))] <- colnames(post)[max.col(post, ties.method = "first")]
      }
    } else {
      new$topic_label <- character()
    }
    bind_rows(known, new) |> arrange(desc(submitted_at))
  })

  output$topics <- renderPlot({
    d <- comment_topics()
    validate(need(nrow(d) > 0, "No comments match these filters."))
    d |>
      count(topic_label) |>
      mutate(pct = n / sum(n), topic_label = reorder(topic_label, pct)) |>
      ggplot(aes(pct, topic_label)) +
      geom_col(width = 0.6, fill = ci_series_colors(1)) +
      geom_text(aes(label = percent(pct, 1)), hjust = -0.2, size = 4.2, color = "#52514E") +
      scale_x_continuous(labels = percent, expand = expansion(mult = c(0, 0.15))) +
      labs(x = "Share of comments", y = NULL, caption = SYNTHETIC_CAPTION) +
      theme_ci(14) + theme(axis.title = element_text(size = rel(0.8), color = "#52514E")) +
      theme(panel.grid.major.y = element_blank())
  }, res = 96)

  output$comments <- renderUI({
    d <- comment_topics()
    if (input$theme_pick != "All themes") d <- filter(d, topic_label == input$theme_pick)
    validate(need(nrow(d) > 0, "No comments for this theme."))
    d |>
      head(25) |>
      select(submitted_at, region, role, score_overall, topic_label, comment) |>
      gt() |>
      cols_label(
        submitted_at = "Date", region = "Region", role = "Role",
        score_overall = "Overall", topic_label = "Theme", comment = "Comment"
      ) |>
      fmt_date(submitted_at, date_style = "yMMMd") |>
      cols_width(comment ~ pct(45)) |>
      tab_source_note("Showing the 25 most recent comments. Synthetic data generated for demonstration purposes only.") |>
      opt_table_font(size = px(13))
  })

  # --- Similar AAR observations ----------------------------------------------

  similar <- eventReactive(input$search, ignoreNULL = FALSE, {
    req(nchar(trimws(input$query)) > 0)
    find_similar(model, input$query, n = 8)
  })

  output$similar <- renderUI({
    s <- similar()
    validate(need(nrow(s) > 0, "No past observations share words with this text. Try more specific wording."))
    s |>
      left_join(select(ci()$aar, aar_id, incident_name, section, observation, recommendation), by = "aar_id") |>
      select(incident_name, section, observation, recommendation, shared_words, similarity) |>
      gt() |>
      fmt_number(similarity, decimals = 2) |>
      cols_label(
        incident_name = "Incident", section = "Type", observation = "Past observation",
        recommendation = "Recommendation", shared_words = "Matched on", similarity = "Similarity"
      ) |>
      tab_source_note(SYNTHETIC_CAPTION) |>
      opt_table_font(size = px(13))
  })
}

shinyApp(ui, server)
