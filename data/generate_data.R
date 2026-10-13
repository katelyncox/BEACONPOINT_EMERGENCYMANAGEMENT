# ---------------------------------------------------------------------------
# Beacon Point EMA - Synthetic data generation
#
# This project contains synthetic data and analysis created for demonstration
# purposes only. Every incident, person, place and comment below is invented.
#
# Creates three related datasets for the agency's Continuous Improvement
# Office, plus a small SQLite database that stands in for the "survey
# responses land in a database" step:
#
#   synthetic-incidents.csv          40 fictional disaster deployments
#   synthetic-survey-responses.csv   ~2,500 post-deployment survey responses
#   synthetic-aar-observations.csv   ~400 after-action report observations
#   synthetic-ci-warehouse.sqlite    the same three tables, queryable with DBI
#
# Run from the project root:  Rscript data/generate_data.R
# ---------------------------------------------------------------------------

library(dplyr)
library(tidyr)
library(purrr)
library(readr)
library(tibble)
library(DBI)

set.seed(20261014)

DATA_END <- as.Date("2026-10-11") # Sunday before the demo; keeps runs identical
KIT_ROLLOUT <- as.Date("2025-07-01") # new mobile field kits issued agency-wide

out_dir <- if (basename(getwd()) == "data") "." else "data"

# --- Reference lists -------------------------------------------------------

regions <- c(
  "Northern Coast", "Eastern Seaboard", "Gulf Coast",
  "Central Plains", "Mountain West", "Pacific Rim"
)

# Incident types each region tends to see
region_hazards <- list(
  "Northern Coast"   = c("Winter Storm", "Flood", "Severe Storm"),
  "Eastern Seaboard" = c("Hurricane", "Flood", "Winter Storm"),
  "Gulf Coast"       = c("Hurricane", "Hurricane", "Flood"),
  "Central Plains"   = c("Tornado", "Severe Storm", "Flood"),
  "Mountain West"    = c("Wildfire", "Winter Storm", "Flood"),
  "Pacific Rim"      = c("Wildfire", "Wildfire", "Severe Storm")
)

# Invented place names, deliberately not real counties
places <- c(
  "Kestrel Valley", "Marrow Bay", "Ashgrove", "Tamsin River", "Cobalt Ridge",
  "Larkspur Flats", "Hollis Delta", "Brindle Pass", "Quillon Basin",
  "Sorrel Point", "Wexmoor", "Juniper Hollow", "Calder Springs",
  "Ottoway Plains", "Fennick Coast", "Pell Harbor", "Rennet Falls",
  "Vantor Lake", "Gilded Mesa", "Thornback Bluffs"
)

roles <- c(
  "Field Staff", "Supervisor", "Reservist",
  "Logistics Specialist", "Liaison Officer"
)

# --- 1. Incidents ----------------------------------------------------------

n_incidents <- 40
start_window <- seq(as.Date("2024-06-01"), as.Date("2026-07-15"), by = "day")

incidents <- tibble(
  region = sample(regions, n_incidents, replace = TRUE),
  start_date = sort(sample(start_window, n_incidents))
) |>
  # Guarantee recent activity so the weekly report always has something new,
  # including the Pacific Rim wildfire behind the late-2026 communication dip
  bind_rows(tibble(
    region = c("Pacific Rim", "Gulf Coast", "Central Plains"),
    start_date = as.Date(c("2026-08-18", "2026-08-30", "2026-09-08"))
  )) |>
  arrange(start_date) |>
  mutate(
    incident_type = map_chr(region, \(r) sample(region_hazards[[r]], 1)),
    incident_type = case_when(
      region == "Pacific Rim" & start_date == as.Date("2026-08-18") ~ "Wildfire",
      region == "Gulf Coast" & start_date == as.Date("2026-08-30") ~ "Hurricane",
      .default = incident_type
    ),
    place = sample(places, n(), replace = TRUE),
    incident_name = paste(place, incident_type),
    incident_id = sprintf(
      "SYN-%s-%03d", format(start_date, "%y"), row_number()
    ),
    duration_days = round(runif(n(), 30, 140)),
    staff_deployed = round(rlnorm(n(), log(60), 0.5)) + 15,
    households_affected = round(rlnorm(n(), log(6000), 0.9))
  ) |>
  select(
    incident_id, incident_name, incident_type, region, start_date,
    duration_days, staff_deployed, households_affected
  )

# --- 2. Survey responses ---------------------------------------------------

clip_likert <- function(x) pmin(pmax(round(x), 1), 5)

responses <- incidents |>
  mutate(n_resp = round(staff_deployed * runif(n(), 0.55, 0.8))) |>
  uncount(n_resp) |>
  mutate(
    # Staff complete the survey when they demobilize, so dates spread across
    # the life of the incident. Anything past DATA_END hasn't happened yet.
    submitted_at = start_date + round(runif(n(), 14, duration_days + 14)),
    role = sample(roles, n(), replace = TRUE, prob = c(.38, .14, .24, .14, .10)),
    first_deployment = if_else(
      runif(n()) < if_else(role == "Reservist", 0.55, 0.15), "Yes", "No"
    ),
    deployment_weeks = pmax(1, round(rgamma(n(), shape = 3, rate = 0.7)))
  ) |>
  filter(submitted_at <= DATA_END) |>
  mutate(
    mood = rnorm(n(), 0, 0.45), # a respondent's general disposition
    post_kit = submitted_at >= KIT_ROLLOUT,
    long_haul = deployment_weeks > 6,
    gulf_hurricane = region == "Gulf Coast" & incident_type == "Hurricane",
    pacific_dip = region == "Pacific Rim" & submitted_at >= as.Date("2026-09-01"),

    score_onboarding = clip_likert(
      3.7 + mood - 1.0 * (first_deployment == "Yes") + rnorm(n(), 0, 0.7)
    ),
    score_tools_tech = clip_likert(
      2.6 + mood + 1.1 * post_kit + rnorm(n(), 0, 0.7)
    ),
    score_communication = clip_likert(
      3.6 + mood - 0.6 * long_haul - 1.2 * pacific_dip + rnorm(n(), 0, 0.7)
    ),
    score_logistics = clip_likert(
      3.5 + mood - 1.2 * gulf_hurricane + rnorm(n(), 0, 0.75)
    ),
    score_leadership = clip_likert(
      3.8 + mood - 0.5 * long_haul + rnorm(n(), 0, 0.65)
    ),
    score_overall = clip_likert(
      (score_onboarding + score_tools_tech + score_communication +
        score_logistics + score_leadership) / 5 + rnorm(n(), 0, 0.45)
    ),
    p_yes = plogis(-4.2 + 1.35 * score_overall),
    redeploy_draw = runif(n()),
    would_redeploy = case_when(
      redeploy_draw < p_yes ~ "Yes",
      redeploy_draw < p_yes + (1 - p_yes) * 0.45 ~ "Unsure",
      .default = "No"
    )
  )

# --- Open-text comments ----------------------------------------------------
# Comments are assembled from theme sentence banks. Which theme a respondent
# writes about depends on which part of the deployment scored worst for them,
# so the text carries the same signal as the ratings. That is what lets topic
# models and keyword analysis recover real patterns later.

sentence_bank <- list(
  technology = list(
    neg = c(
      "The mobile kit arrived without a working hotspot so we had no connectivity in the field for days.",
      "Laptops kept dropping the VPN and the case management system timed out during inspections.",
      "We re-entered inspection data by hand because the tablet app would not sync offline.",
      "Password resets took two days and blocked new staff from the case management system.",
      "Printers and scanners at the field office were broken and nobody owned the help desk tickets.",
      "Connectivity in rural areas was poor and the tablets lost survey data when the signal dropped."
    ),
    pos = c(
      "The new mobile kits worked well and the tablets synced inspection data even with a weak signal.",
      "Having a hotspot and a charged laptop on day one made field inspections much faster.",
      "The help desk resolved system access issues quickly once tickets were submitted."
    )
  ),
  logistics = list(
    neg = c(
      "Lodging was an hour from the disaster recovery center and the commute ate into every shift.",
      "We waited a week for rental vehicles so field teams shared cars and missed appointments.",
      "Hotel rooms were overbooked and staff were moved three times in the first two weeks.",
      "Travel reimbursement was delayed and per diem guidance changed halfway through the deployment.",
      "The staging area ran out of supplies and nobody could tell us when the next delivery would arrive.",
      "Lodging near the impact area was damaged so staff stayed in shelters with no laundry access."
    ),
    pos = c(
      "Lodging and rental vehicles were ready when we arrived which let us start on day one.",
      "The logistics section kept the staging area stocked and posted delivery schedules daily.",
      "Travel booking and reimbursement were smooth this time."
    )
  ),
  communication = list(
    neg = c(
      "We received conflicting guidance from the joint field office and the area field office.",
      "Shift change briefings were skipped so the night team repeated work the day team had finished.",
      "Situation reports came out late and field teams learned about policy changes from survivors.",
      "Leadership updates were sent by email that field staff could not open on their phones.",
      "Nobody explained why priorities changed and the daily briefing was cancelled without notice.",
      "Information about new assistance programs reached the field days after it was announced."
    ),
    pos = c(
      "Daily briefings were short and clear and everyone knew the priorities for the shift.",
      "The situation report was posted every morning which kept field teams aligned.",
      "Leadership explained changes in guidance before they reached the field."
    )
  ),
  onboarding = list(
    neg = c(
      "This was my first deployment and the orientation did not cover how the field office actually works.",
      "Just in time training was a slide deck with no hands on practice using the case system.",
      "I did not receive my position task book until the second week of the deployment.",
      "New staff had no mentor assigned and learned the process by trial and error.",
      "The onboarding checklist was out of date and pointed to systems we no longer use.",
      "Reservists arrived without knowing who their supervisor was or where to report."
    ),
    pos = c(
      "My assigned mentor walked me through the first inspections which built confidence quickly.",
      "The orientation included hands on practice and a clear checklist for the first week.",
      "Just in time training was practical and matched what we did in the field."
    )
  ),
  staffing = list(
    neg = c(
      "Twelve hour shifts for six weeks straight led to fatigue and mistakes in the paperwork.",
      "There was no backfill when people rotated out so the remaining staff covered two roles.",
      "The team was understaffed for the call volume and overtime was the norm for the whole deployment.",
      "Rotation dates kept moving and staff could not plan for time at home.",
      "Supervisors were stretched across too many teams to give feedback or check on wellbeing."
    ),
    pos = c(
      "Rotations were planned in advance and backfill arrived before people demobilized.",
      "Supervisors checked on workload and adjusted shifts when fatigue set in."
    )
  ),
  partners = list(
    neg = c(
      "State liaisons and county emergency managers were using different damage numbers.",
      "Voluntary organizations ran shelters but we had no data sharing agreement to coordinate referrals.",
      "Tribal partners were brought into planning meetings late in the response.",
      "Local officials did not know which field team covered their community."
    ),
    pos = c(
      "Coordination with state liaisons and county emergency managers was strong from the first week.",
      "Voluntary organizations and shelter partners shared referral lists daily which helped survivors.",
      "Joint meetings with tribal and local partners built trust and avoided duplicate work."
    )
  )
)

openers <- c("", "", "", "Overall, ", "Honestly, ", "One thing to note: ", "From my team: ")

write_comment <- function(theme, negative, extra_theme) {
  tone <- if (negative) "neg" else "pos"
  # Most people write a couple of sentences about the same issue
  n_sentences <- sample(1:2, 1, prob = c(0.35, 0.65))
  first <- paste(sample(sentence_bank[[theme]][[tone]], n_sentences), collapse = " ")
  text <- paste0(sample(openers, 1), first)
  # Some comments touch on a second theme as well
  if (!is.na(extra_theme)) {
    text <- paste(text, sample(sentence_bank[[extra_theme]]$neg, 1))
  }
  # Lowercase the first sentence's leading letter after an opener
  sub("^(Overall, |Honestly, |One thing to note: |From my team: )([A-Z])",
    "\\1\\L\\2", text,
    perl = TRUE
  )
}

themes <- names(sentence_bank)

responses <- responses |>
  mutate(
    has_comment = runif(n()) < 0.55,
    # Theme weights: worse scores make a theme more likely to come up
    w_technology = exp(-1.1 * (score_tools_tech - 3)),
    w_logistics = exp(-1.1 * (score_logistics - 3)),
    w_communication = exp(-1.1 * (score_communication - 3)),
    w_onboarding = exp(-1.1 * (score_onboarding - 3)),
    w_staffing = if_else(long_haul, 1.6, 0.5),
    w_partners = 0.6
  ) |>
  rowwise() |>
  mutate(
    theme = sample(themes, 1, prob = c(
      w_technology, w_logistics, w_communication,
      w_onboarding, w_staffing, w_partners
    )),
    theme_score = c(
      technology = score_tools_tech, logistics = score_logistics,
      communication = score_communication, onboarding = score_onboarding,
      staffing = score_leadership, partners = score_overall
    )[[theme]],
    extra = if (runif(1) < 0.15) sample(setdiff(themes, theme), 1) else NA_character_,
    comment = if (has_comment) {
      write_comment(theme, theme_score <= 3, extra)
    } else {
      NA_character_
    }
  ) |>
  ungroup() |>
  arrange(submitted_at) |>
  mutate(response_id = sprintf("R-%05d", row_number())) |>
  select(
    response_id, submitted_at, incident_id, region, incident_type, role,
    first_deployment, deployment_weeks, starts_with("score_"),
    would_redeploy, comment
  )

# --- 3. After-action report observations -----------------------------------
# Each closed incident gets 6-14 observations, written the way AAR teams
# record them: a capability, a strength or area for improvement, the
# observation itself, and a recommendation.

capability_for <- c(
  technology = "Operational Communications",
  logistics = "Logistics and Supply Chain Management",
  communication = "Operational Coordination",
  onboarding = "Planning",
  staffing = "Operational Coordination",
  partners = "Mass Care Services"
)

recommendation_bank <- list(
  technology = c(
    "Issue tested mobile kits with hotspots before deployment.",
    "Add an offline mode check to the tablet pre-deployment checklist.",
    "Stand up a field help desk with a named owner for each office."
  ),
  logistics = c(
    "Pre-negotiate lodging blocks within 30 minutes of recovery centers.",
    "Track rental vehicle requests on a shared daily dashboard.",
    "Publish per diem guidance once at activation and hold it for the deployment."
  ),
  communication = c(
    "Standardize a 15 minute shift change briefing with a written handoff.",
    "Post the daily situation report to a mobile friendly page.",
    "Route policy changes through one channel with a field summary."
  ),
  onboarding = c(
    "Pair every first time deployer with a mentor for the first week.",
    "Replace slide based training with hands on practice in a training environment.",
    "Review the onboarding checklist before each activation."
  ),
  staffing = c(
    "Cap consecutive twelve hour shifts and schedule rest days.",
    "Request backfill two weeks before planned rotations.",
    "Limit supervisor span of control to seven direct reports."
  ),
  partners = c(
    "Execute data sharing agreements with voluntary organizations before hurricane season.",
    "Invite tribal and local partners to the first planning meeting.",
    "Publish a community to field team coverage map for local officials."
  )
)

# Hazard-specific theme mix for AARs
theme_mix <- function(type) {
  base <- c(
    technology = 1, logistics = 1, communication = 1.2,
    onboarding = 0.8, staffing = 0.9, partners = 1
  )
  if (type == "Hurricane") base[c("logistics", "partners")] <- c(2.2, 1.5)
  if (type == "Wildfire") base[c("communication", "technology")] <- c(2, 1.6)
  if (type == "Flood") base["partners"] <- 1.6
  base / sum(base)
}

aar <- incidents |>
  filter(start_date + duration_days <= DATA_END) |>
  mutate(n_obs = sample(6:14, n(), replace = TRUE)) |>
  uncount(n_obs) |>
  rowwise() |>
  mutate(
    theme = sample(themes, 1, prob = theme_mix(incident_type)),
    section = sample(c("Area for Improvement", "Strength"), 1, prob = c(.65, .35)),
    core_capability = capability_for[[theme]],
    observation = sample(
      sentence_bank[[theme]][[if (section == "Strength") "pos" else "neg"]], 1
    ),
    recommendation = if (section == "Strength") {
      "Sustain this practice and document it in the playbook."
    } else {
      sample(recommendation_bank[[theme]], 1)
    }
  ) |>
  ungroup() |>
  group_by(incident_id) |>
  mutate(aar_id = sprintf("%s-OBS-%02d", incident_id, row_number())) |>
  ungroup() |>
  mutate(report_date = start_date + duration_days + 21) |>
  select(
    aar_id, incident_id, incident_name, incident_type, region, report_date,
    core_capability, section, observation, recommendation
  )

# --- Write files -----------------------------------------------------------

header <- c(
  "# SYNTHETIC DATA - generated by AI for a Posit demonstration.",
  "# Beacon Point Emergency Management Agency is fictional. No real people, incidents or agency data.",
  paste0("# Generated by data/generate_data.R (seed 20261014, data through ", DATA_END, ")")
)

write_synthetic_csv <- function(df, name) {
  path <- file.path(out_dir, name)
  writeLines(header, path)
  write_csv(df, path, append = TRUE, col_names = TRUE, na = "")
  message("Wrote ", path, " (", nrow(df), " rows)")
}

write_synthetic_csv(incidents, "synthetic-incidents.csv")
write_synthetic_csv(responses, "synthetic-survey-responses.csv")
write_synthetic_csv(aar, "synthetic-aar-observations.csv")

# SQLite stands in for the agency's survey database. In production this would
# be the Postgres database surveydown writes to, or a Databricks schema.
db_path <- file.path(out_dir, "synthetic-ci-warehouse.sqlite")
if (file.exists(db_path)) file.remove(db_path)
con <- dbConnect(RSQLite::SQLite(), db_path)
dbWriteTable(con, "incidents", mutate(incidents, start_date = as.character(start_date)))
dbWriteTable(con, "survey_responses", responses |>
  mutate(submitted_at = as.character(submitted_at), source = "Synthetic history"))
dbWriteTable(con, "aar_observations", mutate(aar, report_date = as.character(report_date)))
dbWriteTable(con, "about", tibble(note = header))
dbDisconnect(con)
message("Wrote ", db_path)
