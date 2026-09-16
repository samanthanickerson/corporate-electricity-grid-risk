# Computes seven analytical metrics from the integrated ERCOT composite
# dataset (data/processed/integrated_analysis.csv). Reads a persisted
# file only — no in-memory sharing with R/01_import_clean.R or
# R/03_data_integration.R.
#
# Corporate Demand MW / Total Queue MW / Active Queue MW / Withdrawn
# Queue MW are pass-throughs of the integrated dataset's own columns.
# Queue Attrition Rate, Demand Pressure Ratio, and Delivery Gap MW are
# derived. Per the 2026-08-26 methodology decision (docs/decisions.md),
# Demand Pressure Ratio and Delivery Gap MW are both computed against
# `total_queue_mw` — everything ever cumulatively entered the queue,
# regardless of current status — superseding the 2026-08-20 decision to
# use `active_queue_mw`. Samantha chose this after
# `docs/analytical_critique.md`'s robustness check found the active-vs-
# total choice alone swings the Demand Pressure Ratio from ~1.03 to
# ~0.53 — a bigger lever on the headline finding than anything the
# weighting sensitivity analysis (`R/06_sensitivity_analysis.R`) tested.
# `active_queue_mw` is still computed and reported as its own
# pass-through metric (#3 below) — it's just no longer the denominator
# for these two derived metrics. See docs/metric_definitions.md for the
# full data dictionary.
#
# HARD GUARDRAIL (CLAUDE.md): interconnection queue MW is NOT deliverable
# MW. "Delivery Gap MW" is a gap against POTENTIAL future generation
# capacity currently in the interconnection queue, never framed as a gap
# against guaranteed or actual delivered capacity. This framing is
# repeated everywhere this metric is presented — do not drop it.

library(dplyr)
library(tibble)
library(purrr)
library(readr)

#' Compute all seven metrics from one row of MW inputs.
#'
#' Reusable for both the real integrated dataset and the hand-built
#' validation examples in `validate_metric_formulas()`, so the exact
#' same formula implementation is what gets checked against
#' hand-calculated expected values, not a separately-maintained copy.
#'
#' Every derived metric explicitly checks its own division-by-zero and
#' missing-input conditions rather than relying on R's silent NA/Inf
#' propagation — each block below states which condition it's guarding
#' against and why, per the explicit "handle explicitly, never silently
#' convert to zero" requirement.
#'
#' @param corporate_demand_mw,total_queue_mw,active_queue_mw,withdrawn_queue_mw
#'   Single numeric values (length 1). `NA` is a valid input and is
#'   handled explicitly per metric, never silently treated as 0.
#' @return A long-format tibble: metric_name, value, unit, formula,
#'   is_valid, note.
compute_metrics <- function(corporate_demand_mw, total_queue_mw,
                             active_queue_mw, withdrawn_queue_mw) {

  # --- 1-4: direct pass-throughs, no computation ---
  passthroughs <- tibble::tibble(
    metric_name = c(
      "Corporate Demand MW", "Total Queue MW",
      "Active Queue MW", "Withdrawn Queue MW"
    ),
    value = c(corporate_demand_mw, total_queue_mw, active_queue_mw, withdrawn_queue_mw),
    unit = "MW",
    formula = c(
      "corporate_demand_mw (ERCOT Large Load data_center sector, as-of snapshot)",
      "sum(mw_1) across all cumulative-entered Berkeley Lab ERCOT projects",
      "sum(mw_1) where q_status == 'active'",
      "sum(mw_1) where q_status == 'withdrawn'"
    ),
    is_valid = !is.na(value),
    note = dplyr::if_else(
      is.na(value),
      "Missing in the integrated dataset input — not silently treated as zero.",
      "Direct pass-through from data/processed/integrated_analysis.csv, no derivation."
    )
  )

  # --- 5: Queue Attrition Rate = withdrawn_queue_mw / total_queue_mw ---
  # Fraction of everything that ever cumulatively entered the queue
  # that has since been withdrawn. This is a simple cumulative ratio,
  # NOT a cohort/time-to-event attrition rate — the underlying data
  # doesn't track how long a project was in the queue before
  # withdrawing. See docs/metric_definitions.md for that caveat.
  attrition_missing <- is.na(withdrawn_queue_mw) || is.na(total_queue_mw)
  attrition_div_zero <- !attrition_missing && total_queue_mw == 0
  attrition_rate <- if (attrition_missing || attrition_div_zero) {
    NA_real_
  } else {
    withdrawn_queue_mw / total_queue_mw
  }
  attrition_note <- dplyr::case_when(
    attrition_missing ~ "Missing withdrawn_queue_mw or total_queue_mw — not silently treated as zero.",
    attrition_div_zero ~ "total_queue_mw is zero — attrition rate undefined (would require dividing by zero).",
    TRUE ~ "withdrawn_queue_mw / total_queue_mw."
  )

  # --- 6: Demand Pressure Ratio = corporate_demand_mw / total_queue_mw ---
  # How many multiples of everything ever cumulatively entered the
  # supply pipeline would be needed to satisfy current corporate
  # demand. > 1 means demand exceeds total queue capacity; < 1 means
  # total queue capacity exceeds demand. Uses total_queue_mw, not
  # active_queue_mw, per the 2026-08-26 decision (see file header) —
  # supersedes the 2026-08-20 decision.
  pressure_missing <- is.na(corporate_demand_mw) || is.na(total_queue_mw)
  pressure_div_zero <- !pressure_missing && total_queue_mw == 0
  demand_pressure_ratio <- if (pressure_missing || pressure_div_zero) {
    NA_real_
  } else {
    corporate_demand_mw / total_queue_mw
  }
  pressure_note <- dplyr::case_when(
    pressure_missing ~ "Missing corporate_demand_mw or total_queue_mw — not silently treated as zero.",
    pressure_div_zero ~ "total_queue_mw is zero — demand pressure ratio undefined (would require dividing by zero).",
    TRUE ~ "corporate_demand_mw / total_queue_mw."
  )

  # --- 7: Delivery Gap MW = corporate_demand_mw - total_queue_mw ---
  # HARD GUARDRAIL (CLAUDE.md): this is a gap against POTENTIAL future
  # generation capacity currently in the interconnection queue, never
  # against actual or guaranteed deliverable capacity — queue MW is not
  # deliverable MW. Positive = demand exceeds total queue capacity;
  # negative = total queue capacity currently exceeds demand (a
  # meaningful result, not an error). No division here, so no
  # div-by-zero case, but missing inputs are still checked explicitly
  # rather than relying on silent NA propagation.
  gap_missing <- is.na(corporate_demand_mw) || is.na(total_queue_mw)
  delivery_gap_mw <- if (gap_missing) {
    NA_real_
  } else {
    corporate_demand_mw - total_queue_mw
  }
  gap_note <- if (gap_missing) {
    "Missing corporate_demand_mw or total_queue_mw — not silently treated as zero."
  } else {
    paste(
      "corporate_demand_mw - total_queue_mw. Gap against POTENTIAL",
      "future generation capacity in the interconnection queue, NOT",
      "deliverable MW — queue MW is not deliverable MW."
    )
  }

  derived <- tibble::tibble(
    metric_name = c("Queue Attrition Rate", "Demand Pressure Ratio", "Delivery Gap MW"),
    value = c(attrition_rate, demand_pressure_ratio, delivery_gap_mw),
    unit = c("ratio", "ratio", "MW"),
    formula = c(
      "withdrawn_queue_mw / total_queue_mw",
      "corporate_demand_mw / total_queue_mw",
      "corporate_demand_mw - total_queue_mw"
    ),
    is_valid = !is.na(value),
    note = c(attrition_note, pressure_note, gap_note)
  )

  dplyr::bind_rows(passthroughs, derived)
}

#' Hand-built example scenarios covering a normal case, both
#' division-by-zero cases, a missing-input case, a clean round-number
#' attrition check, and a negative-delivery-gap case — run through the
#' same `compute_metrics()` used on real data and checked against
#' hand-calculated expected values.
#'
#' This is a genuine executable self-test (`stop()`s loudly on any
#' mismatch), not just written documentation — in the absence of a
#' formal test framework in this project, and given R still hasn't
#' executed in this environment, this is the first real check these
#' formulas get. The same 6 examples appear as a markdown table in
#' docs/metric_definitions.md.
#'
#' @return A tibble: example_id, description, metric_name, expected,
#'   actual, matches.
validate_metric_formulas <- function() {
  examples <- tibble::tibble(
    example_id = 1:6,
    description = c(
      "Normal case, round numbers",
      "total_queue_mw = 0 (attrition rate AND demand pressure ratio div-by-zero; gap still computes, since it's subtraction, not division)",
      "active_queue_mw = 0, total_queue_mw normal (confirms pressure ratio and gap no longer depend on active_queue_mw at all, per the 2026-08-26 decision)",
      "corporate_demand_mw missing (pressure ratio and gap NA; attrition unaffected)",
      "Clean round-number attrition check",
      "Total queue capacity exceeds demand (negative delivery gap)"
    ),
    corporate_demand_mw = c(400000, 400000, 400000, NA_real_, 100000, 50000),
    total_queue_mw       = c(200000, 0,      200000, 200000,   100000, 200000),
    active_queue_mw      = c(100000, 100000, 0,      100000,   75000,  100000),
    withdrawn_queue_mw   = c(50000,  0,      50000,  50000,    25000,  50000)
  )

  results <- purrr::pmap_dfr(examples, function(example_id, description,
                                                 corporate_demand_mw, total_queue_mw,
                                                 active_queue_mw, withdrawn_queue_mw) {
    compute_metrics(corporate_demand_mw, total_queue_mw, active_queue_mw, withdrawn_queue_mw) %>%
      dplyr::mutate(example_id = example_id, description = description, .before = 1)
  })

  expected <- tibble::tribble(
    ~example_id, ~metric_name,           ~expected,
    1, "Corporate Demand MW",   400000,
    1, "Total Queue MW",        200000,
    1, "Active Queue MW",       100000,
    1, "Withdrawn Queue MW",    50000,
    1, "Queue Attrition Rate",  0.25,
    1, "Demand Pressure Ratio", 2.0,
    1, "Delivery Gap MW",       200000,
    2, "Queue Attrition Rate",  NA_real_,
    2, "Demand Pressure Ratio", NA_real_,
    2, "Delivery Gap MW",       400000,
    3, "Demand Pressure Ratio", 2.0,
    3, "Delivery Gap MW",       200000,
    4, "Demand Pressure Ratio", NA_real_,
    4, "Delivery Gap MW",       NA_real_,
    4, "Queue Attrition Rate",  0.25,
    5, "Queue Attrition Rate",  0.25,
    6, "Delivery Gap MW",       -150000
  )

  checked <- expected %>%
    dplyr::left_join(results, by = c("example_id", "metric_name")) %>%
    dplyr::mutate(
      matches = dplyr::if_else(
        is.na(expected) & is.na(value),
        TRUE,
        !is.na(expected) & !is.na(value) & abs(expected - value) < 1e-9
      )
    ) %>%
    dplyr::select(example_id, description, metric_name, expected, actual = value, matches)

  if (!all(checked$matches)) {
    stop(
      "Metric formula validation failed for example(s): ",
      paste(unique(checked$example_id[!checked$matches]), collapse = ", ")
    )
  }

  checked
}

#' Run the full metrics pipeline: read the integrated dataset, self-
#' validate the formulas against hand-built examples (stopping loudly
#' on any mismatch), compute all seven metrics from the real data, and
#' write the result.
#'
#' @return list(metrics, validation) — `metrics` also written to
#'   `data/processed/analysis_metrics.csv`.
run_metrics_pipeline <- function() {
  integrated <- readr::read_csv("data/processed/integrated_analysis.csv", show_col_types = FALSE)

  if (nrow(integrated) != 1) {
    stop(
      "Expected exactly one row in integrated_analysis.csv (a single ",
      "snapshot, per docs/decisions.md), found ", nrow(integrated)
    )
  }

  # Fails loudly here, before any real metric is written, if the
  # formulas don't match hand-calculated expectations.
  validation <- validate_metric_formulas()

  metrics <- compute_metrics(
    integrated$corporate_demand_mw[[1]], integrated$total_queue_mw[[1]],
    integrated$active_queue_mw[[1]], integrated$withdrawn_queue_mw[[1]]
  ) %>%
    dplyr::mutate(
      geography = integrated$geography[[1]],
      time_period = integrated$time_period[[1]],
      as_of_date = integrated$as_of_date[[1]],
      .before = 1
    )

  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(metrics, "data/processed/analysis_metrics.csv")

  list(metrics = metrics, validation = validation)
}

result <- run_metrics_pipeline()
print(result$metrics)
print(result$validation)
