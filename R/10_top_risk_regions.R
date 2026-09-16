# Builds a factual findings table from the pipeline's already-persisted,
# already-validated final outputs. Computes NOTHING new -- every value
# is a direct pass-through/rename of a number R/03 or R/05 already
# derived and validated; this script only selects, renames, and combines.
#
# Reads:
#   data/processed/integrated_analysis.csv       (R/03_data_integration.R)
#   data/processed/procurement_risk_scores.csv   (R/05_risk_score.R)
# Writes ONLY:
#   output/analysis/top_risk_regions.csv
#
# WHY THIS FILE IS 1 ROW, NOT 10 (docs/decisions.md, 2026-09-03): this
# pipeline's validated dataset contains exactly one region (ERCOT) and
# one snapshot -- there are no other real regions with independently
# computed Corporate Demand MW / Active Queue MW / Demand Pressure /
# Queue Attrition / Queue Age / Delivery Gap / Procurement Risk Score to
# rank. A literal "top 10 highest-risk regions" table cannot be built
# from this data without fabricating 9 rows. Confirmed with Samantha via
# a clarifying question: report the 1 real region only, explicitly
# labeled as such -- never presented as a ranking. `rank`,
# `regions_available_in_dataset`, `regions_requested`, and `note` below
# all exist specifically so this limitation is legible from the CSV
# itself, without needing any conversation's context to understand it.
#
# HARD GUARDRAIL (CLAUDE.md): interconnection queue MW is NOT deliverable
# MW, and the Procurement Risk Score is a methodological construct, not
# objective truth -- both caveats travel in `note` below. No causal
# language anywhere in this file, per the request this table answers.

library(readr)

#' Read the two persisted inputs this table depends on, each asserted to
#' be exactly one row (this pipeline's established single-snapshot
#' shape, docs/decisions.md 2026-08-19/20) -- fails loudly otherwise,
#' matching the guard pattern already used in R/04, R/05, and R/09.
read_top_risk_inputs <- function() {
  integrated <- readr::read_csv("data/processed/integrated_analysis.csv", show_col_types = FALSE)
  risk_scores <- readr::read_csv("data/processed/procurement_risk_scores.csv", show_col_types = FALSE)

  if (nrow(integrated) != 1) {
    stop(
      "Expected exactly one row in integrated_analysis.csv, found ",
      nrow(integrated)
    )
  }
  if (nrow(risk_scores) != 1) {
    stop(
      "Expected exactly one row in procurement_risk_scores.csv, found ",
      nrow(risk_scores)
    )
  }
  if (!identical(integrated$geography[[1]], risk_scores$geography[[1]]) ||
      !identical(integrated$as_of_date[[1]], risk_scores$as_of_date[[1]]) ||
      !identical(integrated$time_period[[1]], risk_scores$time_period[[1]])) {
    stop(
      "integrated_analysis.csv and procurement_risk_scores.csv disagree on ",
      "geography/as_of_date/time_period -- refusing to combine mismatched snapshots."
    )
  }

  list(integrated = integrated, risk_scores = risk_scores)
}

#' Build the one-row findings table.
#'
#' `total_queue_mw` is included alongside `active_queue_mw` even though
#' the request named only "Active Queue MW" -- `demand_pressure_ratio`
#' and `delivery_gap_mw` are computed against `total_queue_mw`, not
#' `active_queue_mw` (R/04_metrics.R, 2026-08-26 decision). Omitting it
#' would leave those two columns unverifiable/apparently inconsistent
#' with the only queue-capacity figure shown, since dividing
#' `corporate_demand_mw` by the visible `active_queue_mw` gives a
#' materially different, wrong number (~1.03 vs. the real ~0.53).
#'
#' The `note` text interpolates the actual `geography` value rather than
#' hardcoding "ERCOT" (matching R/09_tableau_export.R's guard pattern),
#' so this table can never contradict its own `geography` column if this
#' pipeline is ever extended to a different single region.
build_top_risk_regions <- function(integrated, risk_scores) {
  geography <- integrated$geography[[1]]

  tibble::tibble(
    rank = 1L,
    geography = geography,
    as_of_date = integrated$as_of_date[[1]],
    corporate_demand_mw = integrated$corporate_demand_mw[[1]],
    active_queue_mw = integrated$active_queue_mw[[1]],
    total_queue_mw = integrated$total_queue_mw[[1]],
    demand_pressure_ratio = risk_scores$raw_demand_pressure_ratio[[1]],
    queue_attrition_rate = risk_scores$raw_queue_attrition_rate[[1]],
    queue_age_days = risk_scores$raw_queue_age_days[[1]],
    delivery_gap_mw = risk_scores$raw_delivery_gap_mw[[1]],
    procurement_risk_score = risk_scores$procurement_risk_score[[1]],
    regions_available_in_dataset = 1L,
    regions_requested = 10L,
    note = paste0(
      "This dataset contains exactly one region (", geography, ") and ",
      "one snapshot -- a top-10 ranking is not possible from this data. ",
      "This table reports the only region available, not a ranking of ",
      "10. demand_pressure_ratio and delivery_gap_mw are computed ",
      "against total_queue_mw, not active_queue_mw (both are shown ",
      "above for verifiability). Interconnection queue MW is potential ",
      "future capacity, not deliverable or guaranteed MW. The ",
      "Procurement Risk Score is an analytical construct reflecting a ",
      "specific weighting scheme, not objective truth -- see ",
      "output/analysis/risk_score_sensitivity.csv."
    )
  )
}

#' Run the export end to end: read both persisted inputs, combine, write.
#'
#' @return The one-row tibble (also written to disk).
run_top_risk_regions <- function() {
  inputs <- read_top_risk_inputs()
  top_risk_regions <- build_top_risk_regions(inputs$integrated, inputs$risk_scores)

  dir.create("output/analysis", recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(top_risk_regions, "output/analysis/top_risk_regions.csv")

  top_risk_regions
}

result <- run_top_risk_regions()
print(result)
