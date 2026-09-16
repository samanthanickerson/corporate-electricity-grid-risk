# Builds a manually-checkable validation sample: 9 hand-constructed
# example rows (3 high-risk, 3 medium-risk, 3 low-risk), run through the
# exact same, unmodified formulas as the real pipeline, so every number
# in the output can be independently recomputed by hand.
#
# WHY SYNTHETIC, NOT REAL REGIONS: this pipeline has exactly ONE region
# (ERCOT) and ONE snapshot -- confirmed with Samantha via clarifying
# question. The only demand-side source (ERCOT Large Load /
# ercotqueue.com) has no sub-ERCOT geography and no coverage of any
# other grid region, so corporate_demand_mw, Demand Pressure Ratio,
# Delivery Gap MW, and the Procurement Risk Score cannot be genuinely
# computed for any region other than the single real ERCOT observation
# that exists (data/processed/procurement_risk_scores.csv). There is no
# real data to select "9 regions" from. Every row below is an explicit,
# hand-built illustrative construction -- never presented as observed
# ERCOT data -- designed to exercise the real formulas across a spread
# of complete, plausible inputs spanning 3 risk tiers, in the same
# manually-checkable spirit as R/04_metrics.R's
# validate_metric_formulas() and R/05_risk_score.R's
# validate_risk_score_functions(), packaged here as the requested
# standalone CSV deliverable. Unlike those two self-tests, every row
# here has fully-populated inputs by design (realistic, complete
# examples, not edge cases) -- this file does NOT exercise the missing-
# value/div-by-zero/excluded-component code paths; that coverage
# remains the job of R/04's and R/05's own validate_*() functions.
#
# "Do not change any calculations": every formula below is duplicated
# VERBATIM from R/04_metrics.R (compute_metrics()) and
# R/05_risk_score.R (clip_0_100, the four normalize_* functions,
# compute_composite_score, RISK_SCORE_WEIGHTS) -- not reimplemented by
# hand, and not source()d directly (which would re-trigger those
# scripts' own real pipeline runs and overwrite
# analysis_metrics.csv/procurement_risk_scores.csv as a side effect).
# This matches R/06_sensitivity_analysis.R's existing convention of
# duplicating R/05's pure functions rather than sourcing them. IMPORTANT:
# if R/04_metrics.R's compute_metrics() or R/05_risk_score.R's
# normalization/composite-score functions ever change, these copies must
# be updated identically, or this file's numbers will silently stop
# matching the real pipeline's formulas.
#
# Writes ONLY output/analysis/manual_validation_sample.csv. Does not
# read, modify, or overwrite any other file.

library(dplyr)
library(tibble)
library(readr)
library(purrr)

# --- Duplicated verbatim from R/04_metrics.R -----------------------------

#' Compute all seven metrics from one row of MW inputs. Exact copy of
#' R/04_metrics.R's compute_metrics() -- see that file for full formula
#' comments/rationale.
compute_metrics <- function(corporate_demand_mw, total_queue_mw,
                             active_queue_mw, withdrawn_queue_mw) {

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

# --- Duplicated verbatim from R/05_risk_score.R --------------------------

RISK_SCORE_WEIGHTS <- c(
  demand_pressure  = 1 / 6,
  delivery_gap     = 1 / 6,
  queue_attrition  = 1 / 3,
  queue_age        = 1 / 3
)

clip_0_100 <- function(x) {
  pmin(pmax(x, 0), 100)
}

normalize_attrition <- function(x) {
  if (!is.finite(x)) {
    return(NA_real_)
  }
  clip_0_100(x * 100)
}

normalize_demand_pressure <- function(x, min_ref = 0, max_ref = 5.0) {
  if (!is.finite(x)) {
    return(NA_real_)
  }
  clip_0_100((x - min_ref) / (max_ref - min_ref) * 100)
}

# Sign-aware tanh transform (2026-08-26 rescale, docs/decisions.md) --
# exact copy of R/05_risk_score.R's post-rescale normalize_delivery_gap().
normalize_delivery_gap <- function(x, scale = 200000) {
  if (!is.finite(x)) {
    return(NA_real_)
  }
  clip_0_100(50 * (1 + tanh(x / scale)))
}

normalize_queue_age <- function(x, min_ref = 0, max_ref = 3650) {
  if (!is.finite(x)) {
    return(NA_real_)
  }
  clip_0_100((x - min_ref) / (max_ref - min_ref) * 100)
}

compute_composite_score <- function(normalized, weights) {
  valid <- is.finite(normalized)

  if (!any(valid)) {
    return(list(
      score = NA_real_,
      weights_used = weights[FALSE],
      excluded = names(normalized)
    ))
  }

  weights_valid <- weights[valid]
  weights_rescaled <- weights_valid / sum(weights_valid)
  score <- sum(normalized[valid] * weights_rescaled)

  list(
    score = score,
    weights_used = weights_rescaled,
    excluded = names(normalized)[!valid]
  )
}

# --- 9 hand-built synthetic examples --------------------------------------
# Each row is a deliberately constructed combination of raw inputs, not an
# observed ERCOT figure. `raw_queue_age_days` stands in directly for what
# R/05_risk_score.R's compute_queue_age() would normally derive from real
# project-level rows -- there are no real synthetic "projects" to derive
# it from, so it's supplied directly. Three different mechanisms produce
# a "high" score below (severe demand pressure; extreme demand pressure
# with a large queue; moderate pressure but very high attrition + a fully
# aged queue) so the sample doesn't just repeat one pattern.
SYNTHETIC_EXAMPLES <- tibble::tribble(
  ~example_id, ~risk_tier, ~label,
  ~corporate_demand_mw, ~total_queue_mw, ~active_queue_mw, ~withdrawn_queue_mw, ~raw_queue_age_days,

  1, "high", "Severe demand pressure (demand >> total queue), moderate attrition, old queue",
  500000, 100000, 40000, 55000, 3000,

  2, "high", "Extreme demand pressure with a larger absolute queue, moderate attrition",
  800000, 150000, 90000, 45000, 2500,

  3, "high", "Moderate demand pressure but very high attrition and a fully-aged queue",
  300000, 250000, 50000, 190000, 3650,

  4, "medium", "Demand and total queue exactly balanced, moderate attrition/age",
  400000, 400000, 250000, 120000, 1500,

  5, "medium", "Demand modestly exceeds total queue, moderate attrition/age",
  450000, 350000, 200000, 100000, 1800,

  6, "medium", "Total queue modestly exceeds demand, moderate-plus attrition/age",
  350000, 450000, 280000, 140000, 2200,

  7, "low", "Total queue vastly exceeds demand, low attrition, young queue",
  200000, 600000, 500000, 40000, 400,

  8, "low", "Total queue comfortably exceeds demand, very low attrition, young queue",
  150000, 300000, 250000, 15000, 600,

  9, "low", "Demand slightly exceeds total queue, but very low attrition and very young queue",
  220000, 200000, 180000, 10000, 300
)

#' Run one synthetic example through the (duplicated, unmodified) real
#' formulas end to end.
#'
#' @return A one-row tibble of every underlying and derived value.
score_synthetic_example <- function(example_id, risk_tier, label,
                                     corporate_demand_mw, total_queue_mw,
                                     active_queue_mw, withdrawn_queue_mw,
                                     raw_queue_age_days) {
  metrics <- compute_metrics(
    corporate_demand_mw, total_queue_mw, active_queue_mw, withdrawn_queue_mw
  )
  extract <- function(name) metrics$value[metrics$metric_name == name]

  queue_attrition_rate <- extract("Queue Attrition Rate")
  demand_pressure_ratio <- extract("Demand Pressure Ratio")
  delivery_gap_mw <- extract("Delivery Gap MW")

  normalized <- c(
    demand_pressure = normalize_demand_pressure(demand_pressure_ratio),
    delivery_gap    = normalize_delivery_gap(delivery_gap_mw),
    queue_attrition = normalize_attrition(queue_attrition_rate),
    queue_age       = normalize_queue_age(raw_queue_age_days)
  )

  composite <- compute_composite_score(normalized, RISK_SCORE_WEIGHTS)

  weights_used_str <- paste(
    sprintf("%s=%.4f", names(composite$weights_used), composite$weights_used),
    collapse = "; "
  )

  tibble::tibble(
    example_id = example_id,
    risk_tier = risk_tier,
    label = label,
    corporate_demand_mw = corporate_demand_mw,
    total_queue_mw = total_queue_mw,
    active_queue_mw = active_queue_mw,
    withdrawn_queue_mw = withdrawn_queue_mw,
    raw_queue_age_days = raw_queue_age_days,
    queue_attrition_rate = queue_attrition_rate,
    demand_pressure_ratio = demand_pressure_ratio,
    delivery_gap_mw = delivery_gap_mw,
    norm_demand_pressure = normalized[["demand_pressure"]],
    norm_delivery_gap = normalized[["delivery_gap"]],
    norm_queue_attrition = normalized[["queue_attrition"]],
    norm_queue_age = normalized[["queue_age"]],
    procurement_risk_score = composite$score,
    weights_used = weights_used_str,
    note = paste(
      "Synthetic illustrative example, not a real ERCOT observation --",
      "computed via the unmodified formulas duplicated from",
      "R/04_metrics.R (compute_metrics()) and R/05_risk_score.R",
      "(normalize_*(), compute_composite_score()). raw_queue_age_days is",
      "a hand-supplied stand-in for what compute_queue_age() would",
      "normally derive from real project-level rows."
    )
  )
}

#' Build the full 9-row validation sample and write it to disk.
run_manual_validation_sample <- function() {
  result <- purrr::pmap_dfr(SYNTHETIC_EXAMPLES, score_synthetic_example)

  # Sanity check, not a formula test: confirm the hand-picked inputs
  # actually landed in 3 non-overlapping risk bands as intended. If not,
  # the INPUTS need adjusting, never the formulas above.
  #
  # Guarded against a malformed/edited SYNTHETIC_EXAMPLES (e.g. a typo'd
  # risk_tier value, or a tier missing 3 rows) producing a zero-length
  # min_score/max_score for a tier: `&&` on an empty vector throws an
  # unrelated "missing value where TRUE/FALSE needed" error instead of
  # this check's own diagnostic stop() message -- exactly the kind of
  # edit this check's error message invites someone to make. Asserting
  # all 3 tiers are present with exactly 3 rows first turns that failure
  # mode into the same actionable message instead.
  tier_ranges <- result %>%
    dplyr::group_by(risk_tier) %>%
    dplyr::summarise(
      n = dplyr::n(),
      min_score = min(procurement_risk_score),
      max_score = max(procurement_risk_score),
      .groups = "drop"
    )
  malformed <- !setequal(tier_ranges$risk_tier, c("high", "medium", "low")) ||
    !all(tier_ranges$n == 3)

  if (malformed) {
    stop(
      "SYNTHETIC_EXAMPLES must contain exactly 3 rows each of risk_tier ",
      "'high', 'medium', 'low' -- found: ",
      paste(capture.output(print(tier_ranges)), collapse = " | ")
    )
  }

  high_min <- tier_ranges$min_score[tier_ranges$risk_tier == "high"]
  medium_range <- tier_ranges[tier_ranges$risk_tier == "medium", ]
  low_max <- tier_ranges$max_score[tier_ranges$risk_tier == "low"]

  if (!(high_min > medium_range$max_score && medium_range$min_score > low_max)) {
    stop(
      "Synthetic examples did not land in separated risk bands as intended -- ",
      "adjust the hand-picked inputs in SYNTHETIC_EXAMPLES, not the formulas. ",
      "Tier ranges: ", paste(capture.output(print(tier_ranges)), collapse = " | ")
    )
  }

  dir.create("output/analysis", recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(result, "output/analysis/manual_validation_sample.csv")

  result
}

result <- run_manual_validation_sample()
print(result)
