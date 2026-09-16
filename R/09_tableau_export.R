# Builds the single Tableau-ready dashboard dataset from the pipeline's
# three already-persisted final outputs. Computes NOTHING new -- every
# value here is a direct pass-through/rename of a number R/03, R/05, or
# R/06 already derived and validated; this script only selects, renames,
# and combines. The ONE exception is `state_for_map`, a fabricated
# literal (not sourced from any upstream file) -- see the field's own
# comment below for why, and its guard.
#
# Reads:
#   data/processed/integrated_analysis.csv       (R/03_data_integration.R)
#   data/processed/procurement_risk_scores.csv   (R/05_risk_score.R)
#   output/analysis/risk_score_sensitivity.csv   (R/06_sensitivity_analysis.R)
# Writes ONLY:
#   data/processed/tableau_final.csv
#
# `state_for_map` (added below, literal "Texas") is a presentation-only
# map field for Tableau -- see docs/decisions.md, 2026-08-28. It does
# NOT change or stand in for this pipeline's actual geographic filter,
# which remains `region=='ERCOT'` everywhere else (docs/decisions.md,
# 2026-08-17). Filling the whole state of Texas is a labeled
# approximation for a single-region indicator, since ERCOT's real
# footprint is not identical to the state boundary. Guarded below against
# ever being written for a non-ERCOT snapshot.
#
# `operational_queue_mw`/`suspended_queue_mw` (also computed by R/03) are
# deliberately NOT carried into this export -- no requested Tableau use
# case needs them, and CLAUDE.md's "no unnecessary intermediate fields"
# guidance for this export favors a lean schema. Full breakdown remains
# available in data/processed/integrated_analysis.csv if ever needed.
#
# HARD GUARDRAIL (CLAUDE.md), carried into tableau/README.md: interconnection
# queue MW is NOT deliverable MW, and the Procurement Risk Score is a
# methodological construct, not objective truth -- always presented with
# its weighting scheme AND sensitivity results alongside it, never as a
# bare ranking. That's why this export also reads R/06's sensitivity
# output, not just R/05's single composite score.

library(dplyr)
library(readr)

#' Read the three persisted inputs this export depends on. The two
#' single-snapshot files are each asserted to be exactly one row (this
#' pipeline's established single-snapshot shape, docs/decisions.md
#' 2026-08-19/20) -- fails loudly otherwise, matching the
#' `nrow(...) != 1` guard already used in R/04 and R/05. The sensitivity
#' file is asserted to contain exactly the 3 named scenarios R/06 defines.
read_tableau_export_inputs <- function() {
  integrated <- readr::read_csv("data/processed/integrated_analysis.csv", show_col_types = FALSE)
  risk_scores <- readr::read_csv("data/processed/procurement_risk_scores.csv", show_col_types = FALSE)
  sensitivity <- readr::read_csv("output/analysis/risk_score_sensitivity.csv", show_col_types = FALSE)

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
  if (!setequal(sensitivity$scenario, c("base_case", "demand_pressure_heavy", "queue_risk_heavy"))) {
    stop(
      "Expected exactly the 3 scenarios base_case/demand_pressure_heavy/",
      "queue_risk_heavy in risk_score_sensitivity.csv, found: ",
      paste(unique(sensitivity$scenario), collapse = ", ")
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

  list(integrated = integrated, risk_scores = risk_scores, sensitivity = sensitivity)
}

#' Combine the three inputs into the wide, renamed Tableau schema. A
#' plain column bind, not a key-based join -- all inputs are already
#' confirmed (above) to describe the same single snapshot.
#'
#' `state_for_map` is only ever stamped "Texas" when `geography` is
#' confirmed to be "ERCOT" -- this pipeline is single-region today, but
#' if that ever changes, this guard fails loudly rather than silently
#' mislabeling a non-Texas snapshot's map (see file header).
#'
#' The `weight_*` columns are numeric (read from the sensitivity file's
#' base_case row, where R/06 already writes them as plain numbers) so
#' Tableau calculated fields can use them directly -- `weights_used`
#' (a formatted string from R/05) is kept alongside for human-readable
#' display, not as the only source of the weights.
#'
#' The `sensitivity_*` columns satisfy CLAUDE.md's hard guardrail that
#' the Procurement Risk Score must be presented with its sensitivity
#' results alongside it, not just its weighting scheme -- `base_case`'s
#' score is already `procurement_risk_score` above, so only the two
#' alternative scenarios are added here.
build_tableau_final <- function(integrated, risk_scores, sensitivity) {
  if (!identical(integrated$geography[[1]], "ERCOT")) {
    stop(
      "state_for_map = \"Texas\" is only valid for geography == \"ERCOT\" ",
      "(docs/decisions.md, 2026-08-28) -- found geography = \"",
      integrated$geography[[1]], "\". Refusing to write a mislabeled map field."
    )
  }

  base_case <- dplyr::filter(sensitivity, scenario == "base_case")
  demand_heavy <- dplyr::filter(sensitivity, scenario == "demand_pressure_heavy")
  queue_heavy <- dplyr::filter(sensitivity, scenario == "queue_risk_heavy")

  tibble::tibble(
    geography = integrated$geography[[1]],
    state_for_map = "Texas",
    time_period = integrated$time_period[[1]],
    as_of_date = integrated$as_of_date[[1]],
    corporate_demand_mw = integrated$corporate_demand_mw[[1]],
    total_queue_mw = integrated$total_queue_mw[[1]],
    active_queue_mw = integrated$active_queue_mw[[1]],
    withdrawn_queue_mw = integrated$withdrawn_queue_mw[[1]],
    n_projects_in_scope = integrated$n_projects_in_scope[[1]],
    demand_pressure_ratio = risk_scores$raw_demand_pressure_ratio[[1]],
    delivery_gap_mw = risk_scores$raw_delivery_gap_mw[[1]],
    queue_attrition_rate = risk_scores$raw_queue_attrition_rate[[1]],
    queue_age_days = risk_scores$raw_queue_age_days[[1]],
    n_active_projects_for_queue_age = risk_scores$n_active_projects_for_queue_age[[1]],
    norm_demand_pressure = risk_scores$norm_demand_pressure[[1]],
    norm_delivery_gap = risk_scores$norm_delivery_gap[[1]],
    norm_queue_attrition = risk_scores$norm_queue_attrition[[1]],
    norm_queue_age = risk_scores$norm_queue_age[[1]],
    procurement_risk_score = risk_scores$procurement_risk_score[[1]],
    excluded_components = risk_scores$excluded_components[[1]],
    weights_used = risk_scores$weights_used[[1]],
    weight_demand_pressure = base_case$weight_demand_pressure[[1]],
    weight_delivery_gap = base_case$weight_delivery_gap[[1]],
    weight_queue_attrition = base_case$weight_queue_attrition[[1]],
    weight_queue_age = base_case$weight_queue_age[[1]],
    sensitivity_score_demand_pressure_heavy = demand_heavy$procurement_risk_score[[1]],
    sensitivity_score_vs_base_demand_pressure_heavy = demand_heavy$score_vs_base[[1]],
    sensitivity_primary_driver_demand_pressure_heavy = demand_heavy$primary_driver[[1]],
    sensitivity_score_queue_risk_heavy = queue_heavy$procurement_risk_score[[1]],
    sensitivity_score_vs_base_queue_risk_heavy = queue_heavy$score_vs_base[[1]],
    sensitivity_primary_driver_queue_risk_heavy = queue_heavy$primary_driver[[1]]
  )
}

#' Run the export end to end: read both persisted inputs, combine, write.
#'
#' @return The one-row tibble (also written to disk).
run_tableau_export <- function() {
  inputs <- read_tableau_export_inputs()
  tableau_final <- build_tableau_final(inputs$integrated, inputs$risk_scores, inputs$sensitivity)

  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(tableau_final, "data/processed/tableau_final.csv")

  tableau_final
}

result <- run_tableau_export()
print(result)
