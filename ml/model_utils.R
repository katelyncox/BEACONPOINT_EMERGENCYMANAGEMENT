# ---------------------------------------------------------------------------
# Beacon Point EMA - text analysis utilities
#
# This project contains synthetic data and analysis created for demonstration
# purposes only.
#
# Deterministic, explainable text methods. Nothing here is generative AI:
#   - tokenize and count words (tidytext)
#   - LDA topic model with a fixed seed: the same text always gets the same topics
#   - TF-IDF + cosine similarity to find past AAR observations like a new one,
#     reporting the shared words so an analyst can see *why* they matched
# ---------------------------------------------------------------------------

library(dplyr)
library(tidytext)

MODEL_PATH <- function() ci_path("ml", "text_model.rds")

# Words common to nearly every comment that carry no meaning on their own.
# Keeping this list short and visible is part of making the method explainable.
DOMAIN_STOP_WORDS <- c(
  "field", "staff", "team", "teams", "deployment", "day", "days", "week",
  "weeks", "time", "times", "overall", "honestly", "note", "nobody",
  # generic verbs that show up under every theme
  "arrived", "people", "covered", "set", "checked", "learned", "reached",
  "shared", "built", "included", "moved", "ran", "ate"
)

# Analyst-facing names for the themes. Topics are matched to these by the
# keywords below; analysts confirm or override the match in train_model.R.
THEME_KEYWORDS <- list(
  "Technology & connectivity" = c("connectivity", "laptops", "tablet", "tablets", "hotspot", "vpn", "sync", "signal", "mobile", "kits", "help", "desk", "system", "printers", "password"),
  "Lodging & logistics" = c("lodging", "hotel", "rental", "vehicles", "reimbursement", "per", "diem", "staging", "supplies", "travel", "delivery", "rooms"),
  "Briefings & communication" = c("briefings", "briefing", "guidance", "shift", "change", "situation", "report", "updates", "email", "priorities", "office", "conflicting"),
  "Onboarding & training" = c("orientation", "training", "mentor", "onboarding", "checklist", "task", "book", "practice", "reservists", "deployer", "hands"),
  "Staffing & fatigue" = c("shifts", "fatigue", "backfill", "rotation", "rotations", "understaffed", "overtime", "supervisors", "workload", "hour"),
  "Partner coordination" = c("partners", "liaisons", "county", "voluntary", "organizations", "shelters", "tribal", "local", "officials", "agreement", "coordination", "referral")
)

# Split text into one row per meaningful word
tokenize_text <- function(df, id_col, text_col) {
  df |>
    select(doc_id = {{ id_col }}, text = {{ text_col }}) |>
    filter(!is.na(text)) |>
    unnest_tokens(word, text) |>
    anti_join(stop_words, by = "word") |>
    filter(!word %in% DOMAIN_STOP_WORDS, !grepl("[0-9]", word))
}

# Match each topic to the closest named theme by how much of the topic's
# probability mass falls on that theme's keywords. One theme per topic.
propose_topic_labels <- function(lda) {
  beta <- tidy(lda, matrix = "beta")
  score <- sapply(THEME_KEYWORDS, \(kw) {
    beta |>
      group_by(topic) |>
      summarise(s = sum(beta[term %in% kw])) |>
      arrange(topic) |>
      pull(s)
  })
  labels <- character(nrow(score))
  for (i in seq_len(nrow(score))) {
    best <- which(score == max(score), arr.ind = TRUE)[1, ]
    labels[best[1]] <- colnames(score)[best[2]]
    score[best[1], ] <- -Inf
    score[, best[2]] <- -Inf
  }
  labels
}

# Topic probabilities for new text, using the trained model's vocabulary
assign_topics <- function(model, texts) {
  tokens <- tokenize_text(
    tibble(id = seq_along(texts), text = texts), id, text
  ) |>
    filter(word %in% model$vocab)
  if (nrow(tokens) == 0) {
    return(NULL)
  }
  dtm <- tokens |>
    count(doc_id, word) |>
    cast_dtm(doc_id, word, n)
  post <- topicmodels::posterior(model$lda, newdata = dtm)$topics
  colnames(post) <- model$topic_labels
  post
}

# Build the TF-IDF matrix used for similarity search
build_tfidf <- function(tokens) {
  tf <- tokens |>
    count(doc_id, word) |>
    bind_tf_idf(word, doc_id, n)
  idf <- tf |>
    distinct(word, idf) |>
    (\(d) setNames(d$idf, d$word))()
  mat <- tf |>
    cast_sparse(doc_id, word, tf_idf) |>
    as.matrix()
  mat <- mat / sqrt(rowSums(mat^2)) # unit length, so dot product = cosine
  list(matrix = mat, idf = idf)
}

# Find the past observations most similar to a piece of free text.
# Returns the similarity score and the words the two texts share.
find_similar <- function(model, query, n = 10) {
  q_tokens <- tokenize_text(tibble(id = 1, text = query), id, text)
  words <- intersect(q_tokens$word, colnames(model$tfidf$matrix))
  if (length(words) == 0) {
    return(tibble())
  }
  q <- table(q_tokens$word[q_tokens$word %in% words])
  q_vec <- setNames(numeric(ncol(model$tfidf$matrix)), colnames(model$tfidf$matrix))
  q_vec[names(q)] <- as.numeric(q) / sum(q) * model$tfidf$idf[names(q)]
  q_vec <- q_vec / sqrt(sum(q_vec^2))

  sims <- as.vector(model$tfidf$matrix %*% q_vec)
  top <- order(sims, decreasing = TRUE)[seq_len(min(n, sum(sims > 0)))]

  tibble(
    aar_id = rownames(model$tfidf$matrix)[top],
    similarity = sims[top],
    shared_words = vapply(top, \(i) {
      row <- model$tfidf$matrix[i, words]
      paste(names(sort(row[row > 0], decreasing = TRUE)), collapse = ", ")
    }, character(1))
  )
}
