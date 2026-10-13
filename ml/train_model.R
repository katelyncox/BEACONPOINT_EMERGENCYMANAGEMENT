# ---------------------------------------------------------------------------
# Beacon Point EMA - train the text model
#
# This project contains synthetic data and analysis created for demonstration
# purposes only.
#
# Fits a six-topic LDA model on survey comments and after-action report (AAR)
# observations, names the topics, and builds the TF-IDF index used for
# "find similar observations". The fixed seed makes every run identical,
# which is what reviewers need to trust and reproduce the result.
#
# Run from the project root:  Rscript ml/train_model.R
# ---------------------------------------------------------------------------

source("R/ci_data.R")
source("ml/model_utils.R")
library(topicmodels)

N_TOPICS <- 6
SEED <- 2026

ci <- load_ci_data(sync_live = FALSE)

# --- Corpus: every survey comment plus every AAR observation ---------------

corpus <- bind_rows(
  ci$responses |>
    filter(!is.na(comment)) |>
    transmute(doc_id = response_id, text = comment, source = "Survey comment"),
  # An AAR improvement item is the observation plus its recommendation.
  # Strengths share one boilerplate recommendation, so only the observation
  # is used for them.
  ci$aar |>
    transmute(
      doc_id = aar_id,
      text = if_else(section == "Strength", observation, paste(observation, recommendation)),
      source = "AAR observation"
    )
)

tokens <- tokenize_text(corpus, doc_id, text)
dtm <- tokens |>
  count(doc_id, word) |>
  cast_dtm(doc_id, word, n)

message("Corpus: ", nrow(corpus), " documents, ", ncol(dtm), " distinct words")

# --- Topic model -----------------------------------------------------------

lda <- LDA(
  dtm,
  k = N_TOPICS,
  method = "Gibbs",
  # Survey comments are one or two sentences, so a low alpha (each document
  # leans toward one topic) fits far better than the default of 50 / k.
  control = list(seed = SEED, iter = 1500, burnin = 300, alpha = 0.1, delta = 0.05)
)

topic_labels <- propose_topic_labels(lda)

# Human in the loop: review the top words printed below. If a proposed name
# doesn't fit, override it here by topic number, e.g.
#   LABEL_OVERRIDES <- c("3" = "Shift handoffs")
LABEL_OVERRIDES <- c()
topic_labels[as.integer(names(LABEL_OVERRIDES))] <- LABEL_OVERRIDES

top_terms <- tidy(lda, matrix = "beta") |>
  group_by(topic) |>
  slice_max(beta, n = 10, with_ties = FALSE) |>
  ungroup() |>
  mutate(label = topic_labels[topic])

top_terms |>
  group_by(topic, label) |>
  summarise(words = paste(term, collapse = ", "), .groups = "drop") |>
  (\(d) for (i in seq_len(nrow(d))) message(sprintf("Topic %d [%s]: %s", d$topic[i], d$label[i], d$words[i])))()

# Most likely topic for each training document
doc_topics <- tidy(lda, matrix = "gamma") |>
  group_by(document) |>
  slice_max(gamma, n = 1, with_ties = FALSE) |>
  ungroup() |>
  transmute(doc_id = document, topic, topic_label = topic_labels[topic], gamma)

# --- Similarity index over AAR observations --------------------------------

aar_tokens <- tokens |> filter(doc_id %in% ci$aar$aar_id)
tfidf <- build_tfidf(aar_tokens)

# --- Save ------------------------------------------------------------------

model <- list(
  lda = lda,
  topic_labels = topic_labels,
  top_terms = top_terms,
  doc_topics = doc_topics,
  vocab = colnames(dtm),
  tfidf = tfidf,
  metadata = list(
    trained_at = Sys.time(),
    n_topics = N_TOPICS,
    seed = SEED,
    n_documents = nrow(corpus),
    n_words = ncol(dtm),
    method = "LDA (Gibbs sampling) + TF-IDF cosine similarity"
  )
)

saveRDS(model, MODEL_PATH())
message("Saved ", MODEL_PATH())
