# LLM Text Classification and Evaluation Pipeline for Social Science Research

## Idea

This repository implements a three-phase pipeline for classifying social science text using large language models (LLMs), with a focus on reproducibility and iterative prompt engineering.

### Phase 1 — Model & Prompt Selection (`Scripts/`, `Prompt/`)

A script tests combinations of models (e.g. GPT, Gemini) and prompting strategies (simple zero-shot prompt vs. few-shot prompt) against a gold-standard dataset. Classification tasks are evaluated using binary metrics (F1) or continuous metrics (RMSE) depending on the task type. API credentials are stored separately in `Access_Tokens_Keys/`.

> ⚠️ **Note:** Be mindful of API costs — paid vs. unpaid model tiers differ substantially in price.

### Phase 2 — Error Analysis

Once results are in, misclassifications are inspected through a structured review table that breaks down outcomes by TP / TN / FP / FN, with the original text alongside the model's decision. A helper function appends new examples to this table. Improvements are made **one change at a time** so the effect of each adjustment on outcomes can be isolated.

### Phase 3 — Finalised Classifier (`Output/`)

With a model selected, the prompt is refined with:
- Adapted task description and illustrative examples
- Tie-break rules for borderline cases

The final classifier is run over the full corpus and results are written to `Output/`.

### Repository Structure

| Folder / File | Purpose |
|---|---|
| `Gold_Standard_Data/` | Hand-labelled datasets used for evaluation |
| `Classification_Task/Scripts/` | Classification and evaluation scripts |
| `Classification_Task/Prompt/` | Prompt templates and few-shot example sets |
| `Classification_Task/Output/` | Model outputs and evaluation results |
| `Classification_Task/Access_Tokens_Keys/` | API keys (not version-controlled) |



## Test Datasets

Three datasets are available for evaluating the pipeline.

### 1. Social Security Speeches (Binary Classification)

Swiss parliamentary speeches hand-labelled for whether they address the topic of social security.

- **File:** `df_classify.csv`
- **Size:** 6,321 classified speeches
- **Columns:**
  - `ID` — unique identifier for the speech
  - `text` — full text of the speech
  - `human_assessed_rel` — `0` = not related to social security, `1` = related to social security

### 2. Biodiversity Sentences (Binary Classification)

- **File:** `biodiversität_labelhuman_labelembed2discover.csv`
- **Size:** 2,537 sentences
- **Language:** German
- **Source:** Swiss parliamentary *Geschäfte* (pursuits) — Federal Council drafts, motions, interpellations, initiatives, and requests — spanning multiple legislative periods

Each sentence is classified as to whether it addresses a biodiversity topic. The dataset includes both a human annotation and an automated label produced by *embed2discover* (an embedding-based retrieval method), enabling direct comparison of human vs. automated labelling performance.

**Columns:**

| Column | Description |
|---|---|
| `sentence` | Raw German sentence extracted from a parliamentary document |
| `label_human` | Human annotation: `1` = biodiversity-related, `0` = not related |
| `label_embed2discover` | Automated label from the embed2discover method: `1` = biodiversity-related, `0` = not related |
| `corpus_filename` | Path to the source document within the corpus (format: `period/documentID.txt`) |
| `start_pos` | Character offset where the sentence begins in the source document |
| `end_pos` | Character offset where the sentence ends in the source document |
| `file` | Duplicate of `corpus_filename` |


### 3. Pursuits by Regulation Schema (9-Class Classification)

Each pursuit is placed in a 3×3 grid defined by **regulatory instrument** (columns) and **direction of change** (rows).

| Direction of change | Spending / Investing | Oversight / Implementation | Authorisation |
|---|---|---|---|
| **New** (*Beabsichtigt*) | 1 — e.g. new subsidies (*Subventionen*) | 4 — e.g. new authorisation form | 7 — e.g. new pharma guidelines / new prohibition |
| **Increase** (*Ausweitung*) | 2 — e.g. additional subsidies | 5 — e.g. stronger border/customs staffing | 8 — e.g. expansion of the commons (*Allmende*) |
| **Decrease / Annulment** (*Annullation*) | 3 — e.g. liberalisation (*Liberalisierung*) | 6 — e.g. less bureaucracy | 9 — e.g. loosening of standards / exemptions |



