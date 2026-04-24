# ============================================================
# Step1_pipeline.R
## Description.
# ============================================================


## Load libraries
suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(arrow)
  library(readr)
  library(tidyverse)
  library(tibble)
  library(parallel)
  library(patchwork)
  library(scales)
})

colors10 <- c("#A8322D", "#D88039", "#EFCA08", "#03440C", "#73A580","#202C59", "#2E86AB", "#A1B5D8", "#B594B6", "#731D84")


# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

## Helper: send one batch to the API (internal)
send_batch <- function(batch, prompt, model, base_url, api_key, max_retries = 3) {
  
  call_api <- function(texts) {
    user_content <- paste(texts, collapse = "\n---\n")
    resp <- httr2::request(paste0(base_url, "/chat/completions")) |>
      httr2::req_headers(Authorization = paste("Bearer", api_key)) |>
      httr2::req_body_json(list(
        model    = model,
        messages = list(
          list(role = "system", content = prompt),
          list(role = "user",   content = user_content)
        ),
        temperature     = 0.1,
        max_tokens      = 2000L,
        response_format = list(
          type        = "json_schema",
          json_schema = list(
            name   = "Classification",
            strict = TRUE,
            schema = list(
              type       = "object",
              properties = list(
                items = list(
                  type  = "array",
                  items = list(
                    type       = "object",
                    properties = list(
                      r = list(type = "integer", enum = list(0L, 1L, 2L, 3L)),
                      b = list(type = "boolean")
                    ),
                    required             = list("r", "b"),
                    additionalProperties = FALSE
                  )
                )
              ),
              required             = list("items"),
              additionalProperties = FALSE
            )
          )
        )
      ), auto_unbox = TRUE) |>
      httr2::req_timeout(180) |>
      httr2::req_perform()
    
    content <- httr2::resp_body_json(resp, simplifyVector = FALSE)
    jsonlite::fromJSON(content$choices[[1]]$message$content)$items
  }
  
  # Try the full batch first
  for (attempt in seq_len(max_retries)) {
    items <- call_api(batch$text)
    if (nrow(items) == nrow(batch)) return(tibble::as_tibble(items))
    message(sprintf("  Warning: expected %d items, got %d. Retrying (%d/%d)...",
                    nrow(batch), nrow(items), attempt, max_retries))
  }
  
  # Fallback: one text at a time
  message("  Falling back to one-by-one for this batch...")
  results <- lapply(batch$text, function(txt) {
    as_tibble(call_api(txt))
  })
  bind_rows(results)
}

# classify(): run a model over all texts, return dt + r + b
classify <- function(data, prompt, model, base_url, api_key, 
                     batch_size = 10, r_col = "r", b_col = "b") {
  
  batches   <- split(data, ceiling(seq_len(nrow(data)) / batch_size))
  n_batches <- length(batches)
  
  message(sprintf("\nModel: %s | %d texts | %d batches of %d",
                  model, nrow(data), n_batches, batch_size))
  
  results <- vector("list", n_batches)
  for (i in seq_along(batches)) {
    message(sprintf("  Batch %d / %d ...", i, n_batches))
    results[[i]] <- send_batch(batches[[i]], prompt, model, base_url, api_key)
  }
  
  classifications <- dplyr::bind_rows(results)
  data[[r_col]] <- classifications$r
  data[[b_col]] <- classifications$b
  data
}

## Evaluation function
evaluate_model <- function(predicted, actual, target = 1) {
  tp <- sum(predicted == target & actual == target)
  fp <- sum(predicted == target & actual != target)
  fn <- sum(predicted != target & actual == target)
  tn <- sum(predicted != target & actual != target)
  
  precision <- tp / (tp + fp)
  recall    <- tp / (tp + fn)
  f1        <- 2 * precision * recall / (precision + recall)
  accuracy  <- (tp + tn) / length(actual)
  
  tibble(precision = precision, recall = recall, f1 = f1, accuracy = accuracy)
}

# ------------------------------------------------------------
# 1) Load data
# ------------------------------------------------------------

dt <- read.csv("Gold_Standard_Data/df_classify.csv")
dt[1,]


# ------------------------------------------------------------
# 2) Load prompt
# ------------------------------------------------------------

source("Classification_Task/Prompt/prompt_socialSecurity.R")
## prompt <- r"(
## You are a strict classifier of parliamentary speeches.
## ..."

# ------------------------------------------------------------
# 3) Load key
# ------------------------------------------------------------

# gpt_APIkey object contains the GPT key
source("Classification_Task/Access_Tokens_Keys/LB_gptKEY.R") 

## OR_APIkey
source("Classification_Task/Access_Tokens_Keys/LB_openRouter_KEY.R")

# ------------------------------------------------------------
# 4) Run GPT
# ------------------------------------------------------------
results_gpt <- classify(
  data     = dt[1:5,],
  prompt   = prompt,
  model    = "gpt-4o",
  base_url = "https://api.openai.com/v1",
  api_key  = gpt_APIkey,
  batch_size = 1, 
  r_col      = "r_gpt",
  b_col      = "b_gpt"
)

## or via openRouter: 
results_gpt_or <- classify(
  data     = dt[1:100,],
  prompt   = prompt,
  model    = "openai/gpt-4o",
  base_url = "https://openrouter.ai/api/v1",
  api_key  = OR_APIkey,
  batch_size = 5, 
  r_col      = "r_gpt_or",
  b_col      = "b_gpt_or"
)


# ------------------------------------------------------------
# 4) Run qwen/qwen3.5-27b
# Comment LB: slower (100 items, took about 15min)
# ------------------------------------------------------------
results_gwen_or <- classify(
  data     = dt[1:100,],
  prompt   = prompt,
  model    = "qwen/qwen3.5-27b",
  base_url = "https://openrouter.ai/api/v1",
  api_key  = OR_APIkey,
  batch_size = 5, 
  r_col      = "r_gwen35_or",
  b_col      = "b_gwen35_or"
)


# ------------------------------------------------------------
# 4) Run meta-llama/llama-3.1-8b-instruct
# ------------------------------------------------------------
results_llama_or <- classify(
  data     = dt[1:100,],
  prompt   = prompt,
  model    = "meta-llama/llama-3.1-8b-instruct",
  base_url = "https://openrouter.ai/api/v1",
  api_key  = OR_APIkey,
  batch_size = 1, 
  r_col      = "r_llama_or",
  b_col      = "b_llama_or"
)


# ------------------------------------------------------------
# 5) Collect results
# ------------------------------------------------------------
results_all <- results_gpt_or |>
  left_join(results_gwen_or |> select(id, r_gwen35_or, b_gwen35_or), by = "id") %>% 
  left_join(results_llama_or |> select(id, r_llama_or, b_llama_or), by = "id")


# ------------------------------------------------------------
# 6) Compare
# ------------------------------------------------------------

## GPT: 
evaluate_model(results_all$r_gpt_or, results_all$human_assessed_relevant)

## Gwen
evaluate_model(results_all$r_gwen35_or, results_all$human_assessed_relevant)

## Llama
evaluate_model(results_all$r_llama_or, results_all$human_assessed_relevant)


# ------------------------------------------------------------
# 7) Plot models
# ------------------------------------------------------------

# add or remove rows here — the plot adapts automatically
metrics <- bind_rows(
  evaluate_model(results_all$r_gpt_or,    results_all$human_assessed_relevant) |> mutate(model = "GPT-4o"),
  evaluate_model(results_all$r_gwen35_or, results_all$human_assessed_relevant) |> mutate(model = "Qwen 2.5"),
  evaluate_model(results_all$r_llama_or,  results_all$human_assessed_relevant) |> mutate(model = "Llama 3.3")
) |>
  mutate(model = factor(model, levels = unique(model)))

# ── precision · recall · F1 — grouped bar ─────────────────────────────────
p1 <- metrics |>
  pivot_longer(c(precision, recall, f1), names_to = "metric", values_to = "value") |>
  mutate(metric = factor(metric,
                         levels = c("precision", "recall", "f1"),
                         labels = c("Precision", "Recall", "F1"))) |>
  ggplot(aes(x = metric, y = value, fill = model)) +
  geom_col(position = position_dodge(0.75), width = 0.65) +
  geom_text(aes(label = round(value, 2)),
            position = position_dodge(0.75),
            vjust = -0.4, size = 3, colour = "grey30") +
  scale_fill_manual(values = colors10[c(1,3,5)]) +
  scale_y_continuous(limits = c(0, 1), labels = percent_format(accuracy = 1)) +
  labs(x = NULL, y = NULL, fill = NULL, title = "Precision · Recall · F1") +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    legend.position    = "bottom",
    plot.title         = element_text(size = 12, colour = "grey40")
  ) +
  coord_cartesian(clip = "off") 

# ── accuracy — lollipop ────────────────────────────────────────────────────
p2 <- metrics |>
  ggplot(aes(x = model, y = accuracy, colour = model)) +
  geom_segment(aes(xend = model, y = 0, yend = accuracy), linewidth = 1.2) +
  geom_point(size = 5) +
  geom_text(aes(label = round(accuracy, 2)),
            vjust = -1, size = 3, colour = "grey30") +
  scale_colour_manual(values = colors10[c(1,3,5)]) +
  labs(x = NULL, y = NULL, title = "Accuracy") +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    legend.position    = "none",
    plot.title         = element_text(size = 12, colour = "grey40")
  )+
  scale_y_continuous(limits = c(0, 1), labels = percent_format(accuracy = 1)) +
  coord_cartesian(clip = "off") 

# ── combine ────────────────────────────────────────────────────────────────
p1 + p2 +
  plot_layout(widths = c(2, 1), guides = "collect") &
  theme(legend.position = "bottom")


# ------------------------------------------------------------
# 8) Best model: TABLE!
## which did it get right? 
## which did it get wrong?
# ------------------------------------------------------------

TODO







# ------------------------------------------------------------
# TODO
# ------------------------------------------------------------

## temperature?
## size of the batches (is this form of batching ok?) 
## token limits? => does the full prompt read in? get processed?
## sleeping (within batching!) to allow free models to run

