# Implements the Procurement Risk Score, per the methodology approved in
# docs/risk_score_design.md and the four follow-up decisions made
# 2026-08-20 (see that memo's "Open questions" section, now resolved):
#   1. Demand Pressure Ratio and Delivery Gap MW are mathematically
#      redundant (same two inputs) -- both are kept, each at HALF
#      weight, rather than dropping one.
#   2. Higher Queue Attrition Rate = higher risk (conventional reading).
#   3. Normalization uses PROVISIONAL, explicitly-labeled reference
#      thresholds -- there is only one snapshot observation, so no
#      empirical distribution exists yet to normalize against. Every
#      threshold below is stated plainly as an arbitrary placeholder,
#      not presented as if empirically calibrated.
#   4. A missing component is excluded and the remaining weights are
#      rescaled to sum to 1, documented explicitly whenever it happens.
#
# Reads data/processed/analysis_metrics.csv and
# data/processed/queued_up_clean.csv. Writes ONLY
# data/processed/procurement_risk_scores.csv -- does not touch or
# overwrite integrated_analysis.csv, analysis_metrics.csv,
# queued_up_clean.csv, or ercotqueue_clean.csv, per the project's
# "each stage writes a new file" guardrail.
#
# HARD GUARDRAIL (CLAUDE.md, carried through every prior script this
# session): interconnection queue MW is NOT deliverable MW. This score
# is a composite of potential-capacity and queue-status indicators, not
# a measure of guaranteed future generation.

library(dplyr)
library(tibble)
library(readr)

# --- Weighting scheme -------------------------------------------------
# Three conceptual "slots," each worth 1/3 of the total: (a) demand vs.
# active supply, (b) queue attrition, (c) queue age. Slot (a) is split
# evenly between its two redundant expressions (Demand Pressure Ratio,
# Delivery Gap MW), so that relationship isn't silently double-weighted
# relative to the other two slots.
RISK_SCORE_WEIGHTS <- c(
  demand_pressure  = 1 / 6,
  delivery_gap     = 1 / 6,
  queue_attrition  = 1 / 3,
  queue_age        = 1 / 3
)

# --- Small helpers ------------------------------------------------------

#' Weighted median: the smallest x such that the cumulative weight of
#' values <= x reaches 50% of total weight. No weighted-median function
#' exists elsewhere in this project (or as a current dependency) --
#' implemented directly rather than adding a package for one calculation.
#'
#' @param x,w Numeric vectors of equal length (values and weights).
#' @return A single numeric value, or NA if nothing usable remains after
#'   dropping non-finite/non-positive-weight entries.
weighted_median <- function(x, w) {
  keep <- is.finite(x) & is.finite(w) & w > 0
  x <- x[keep]
  w <- w[keep]
  if (length(x) == 0) {
    return(NA_real_)
  }
  ord <- order(x)
  x <- x[ord]
  w <- w[ord]
  cum_w <- cumsum(w) / sum(w)
  x[which(cum_w >= 0.5)[1]]
}

#' Clip a value to [0, 100] -- the composite score's common scale.
clip_0_100 <- function(x) {
  pmin(pmax(x, 0), 100)
}

# --- Queue Age: the one genuinely new calculation ----------------------
# Not present anywhere else in this project. Computed from the same
# "in-scope" window R/03_data_integration.R already established
# (q_date <= as_of_date, missing q_date excluded), restricted to
# is_active. Uses the MW-weighted MEDIAN, not mean -- a simple mean
# would be badly skewed by Berkeley Lab's 30-year q_date vintage span
# (docs/risk_score_design.md explicitly flags this).

#' @param berkeley_lab Output of reading `data/processed/queued_up_clean.csv`.
#' @param as_of_date The snapshot anchor date (from `analysis_metrics.csv`).
#' @return list(age_days = numeric or NA, n_projects = integer) -- the
#'   project count travels with the value for transparency about its
#'   basis, and reflects only rows `weighted_median()` actually used
#'   (finite age, finite and positive `mw_1`) -- not just every in-scope
#'   active row, which could overstate the true sample if any active row
#'   has `mw_1 <= 0` (flagged elsewhere in the pipeline as
#'   `flag_nonpositive_mw_1`) and would otherwise be silently dropped by
#'   `weighted_median()` without the count reflecting that.
compute_queue_age <- function(berkeley_lab, as_of_date) {
  in_scope_active <- berkeley_lab %>%
    dplyr::filter(!is.na(q_date), q_date <= as_of_date, is_active)

  if (nrow(in_scope_active) == 0) {
    return(list(age_days = NA_real_, n_projects = 0L))
  }

  age_days <- as.numeric(as_of_date - in_scope_active$q_date)
  mw <- in_scope_active$mw_1
  used <- is.finite(age_days) & is.finite(mw) & mw > 0

  list(
    age_days = weighted_median(age_days, mw),
    n_projects = sum(used)
  )
}

# --- Normalization functions --------------------------------------------
# Every function here returns NA_real_ (never 0) for NA or non-finite
# input (Inf/-Inf/NaN) -- "prevent invalid mathematical results" means
# checking is.finite(), not just is.na(), throughout.

#' Queue Attrition Rate is already a true proportion, bounded [0, 1] by
#' construction -- NOT a provisional/arbitrary mapping, unlike the other
#' three components below. Higher attrition = higher risk (2026-08-20
#' decision), so this is a direct rescale, no inversion needed.
normalize_attrition <- function(x) {
  if (!is.finite(x)) {
    return(NA_real_)
  }
  clip_0_100(x * 100)
}

#' PROVISIONAL reference range: 0 (no demand pressure) to 5.0 (demand is
#' 5x total queue capacity, treated as maximum pressure). This ceiling is
#' an arbitrary placeholder, not derived from any empirical distribution
#' -- there is only one snapshot observation to work from. Revisit once
#' real domain thresholds or several months of accumulated snapshots
#' exist.
#'
#' FLAGGED 2026-08-26 (docs/decisions.md): the Demand Pressure Ratio this
#' normalizes switched denominators from active_queue_mw to
#' total_queue_mw. Since total_queue_mw >= active_queue_mw always, the
#' same real-world demand/supply situation now produces a systematically
#' smaller ratio (real snapshot: ~1.03 -> ~0.53) than it would have under
#' the old formula -- and this 5.0 ceiling was never re-examined against
#' that shift. A future recalibration of this threshold should account
#' for it explicitly, not silently inherit a ceiling picked with the old
#' formula's scale in mind.
normalize_demand_pressure <- function(x, min_ref = 0, max_ref = 5.0) {
  if (!is.finite(x)) {
    return(NA_real_)
  }
  clip_0_100((x - min_ref) / (max_ref - min_ref) * 100)
}

#' FIXED 2026-08-26 (docs/decisions.md), replacing a hard linear clip
#' that broke when Delivery Gap MW's base switched from active_queue_mw
#' to total_queue_mw (see git history / the superseded comment this
#' replaced): the old `(x - min_ref) / (max_ref - min_ref)` linear clip
#' hit its -200,000 MW floor outright once the real snapshot's gap became
#' -371,127 MW, and `clip_0_100()` silently flattened that to exactly 0,
#' destroying all magnitude information for that component.
#'
#' Sign-aware bounded transform (`50 * (1 + tanh(x / scale))`), per
#' `docs/risk_score_design.md`'s original recommendation for this
#' component specifically ("a sign-aware scaling... or a bounded
#' transform like tanh... since zero and negative values are meaningful,
#' not edge cases"). Properties that fix the clipping failure:
#' - `x = 0` (exactly balanced) -> exactly 50, same as the old formula's
#'   midpoint.
#' - As `x -> +Inf` (demand vastly exceeds supply) -> approaches 100;
#'   as `x -> -Inf` (supply vastly exceeds demand) -> approaches 0 --
#'   but *asymptotically*, never by a hard floor/ceiling. A realistic
#'   extreme value (e.g. -1,000,000 MW, 5x `scale`) still normalizes to
#'   a small but distinguishable-from-zero score (~0.0045), unlike the old
#'   clip, which zeroed out anything past -200,000 MW identically.
#' - `scale = 200,000` reuses the old linear range's ceiling value
#'   rather than introducing a new arbitrary number -- still an
#'   explicitly PROVISIONAL placeholder (same caveat as every other
#'   normalization in this file; there is only one snapshot to calibrate
#'   against), just applied through a shape that degrades gracefully
#'   instead of destroying information outright.
normalize_delivery_gap <- function(x, scale = 200000) {
  if (!is.finite(x)) {
    return(NA_real_)
  }
  clip_0_100(50 * (1 + tanh(x / scale)))
}

#' PROVISIONAL reference range: 0 days (brand new, minimum risk) to
#' 3,650 days / 10 years (treated as maximum risk). Arbitrary
#' placeholder -- same caveat as the other provisional normalizations.
normalize_queue_age <- function(x, min_ref = 0, max_ref = 3650) {
  if (!is.finite(x)) {
    return(NA_real_)
  }
  clip_0_100((x - min_ref) / (max_ref - min_ref) * 100)
}

# --- Composite score ------------------------------------------------------

#' Combine normalized (0-100) component scores into the final composite,
#' dropping any NA/non-finite component and rescaling remaining weights
#' to sum to 1 (the 2026-08-20 "exclude and re-normalize" decision).
#' Never silently treats a missing component as 0 -- it's excluded from
#' the weighted average entirely, and which components were excluded is
#' returned explicitly rather than only reflected in a bare final number.
#'
#' @param normalized Named numeric vector of 0-100 scores (names must
#'   match `weights`' names); NA/non-finite entries are excluded.
#' @param weights Named numeric vector of weights, summing to 1.
#' @return list(score, weights_used, excluded) -- `weights_used` reflects
#'   the actual rescaled weights applied (equal to `weights` if nothing
#'   was excluded); `excluded` is a character vector of component names
#'   dropped for this run (empty if none).
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

# --- Self-test -------------------------------------------------------------
# Same pattern as 04_metrics.R's validate_metric_formulas(), which caught
# a real arithmetic error last time -- checks normalization clipping at
# both bounds and the missing-component reweighting logic against
# hand-built examples, stop()-ing loudly on any mismatch. The first real
# check these functions get, since R hasn't executed in this environment.
validate_risk_score_functions <- function() {
  checks <- list(
    list(desc = "attrition 0.25 -> 25", actual = normalize_attrition(0.25), expected = 25),
    list(desc = "attrition clipped above 1.0", actual = normalize_attrition(1.5), expected = 100),
    list(desc = "demand pressure at floor (0) -> 0", actual = normalize_demand_pressure(0), expected = 0),
    list(desc = "demand pressure at ceiling (5.0) -> 100", actual = normalize_demand_pressure(5.0), expected = 100),
    list(desc = "demand pressure beyond ceiling clipped", actual = normalize_demand_pressure(10), expected = 100),
    list(desc = "delivery gap at midpoint (0) -> 50", actual = normalize_delivery_gap(0), expected = 50),
    list(desc = "delivery gap at -scale (-200000) -> 50*(1+tanh(-1))", actual = normalize_delivery_gap(-200000), expected = 50 * (1 + tanh(-1))),
    list(desc = "delivery gap at +scale (200000) -> 50*(1+tanh(1))", actual = normalize_delivery_gap(200000), expected = 50 * (1 + tanh(1))),
    list(desc = "delivery gap far beyond scale (-1000000) approaches but never reaches 0", actual = normalize_delivery_gap(-1000000), expected = 50 * (1 + tanh(-5))),
    list(desc = "queue age at floor (0 days) -> 0", actual = normalize_queue_age(0), expected = 0),
    list(desc = "queue age at ceiling (3650 days) -> 100", actual = normalize_queue_age(3650), expected = 100),
    list(desc = "NA input -> NA, not 0", actual = normalize_attrition(NA_real_), expected = NA_real_),
    list(desc = "Inf input -> NA, not 100", actual = normalize_delivery_gap(Inf), expected = NA_real_)
  )

  mismatches <- Filter(function(chk) {
    if (is.na(chk$expected)) {
      !is.na(chk$actual)
    } else {
      is.na(chk$actual) || abs(chk$actual - chk$expected) > 1e-9
    }
  }, checks)

  if (length(mismatches) > 0) {
    stop(
      "Normalization validation failed: ",
      paste(vapply(mismatches, function(m) m$desc, character(1)), collapse = "; ")
    )
  }

  # Missing-component reweighting check: if queue_age is NA, its weight
  # (1/3) should be redistributed proportionally across the other three,
  # which should then sum back to 1.
  composite_with_missing <- compute_composite_score(
    c(demand_pressure = 50, delivery_gap = 50, queue_attrition = 50, queue_age = NA_real_),
    RISK_SCORE_WEIGHTS
  )
  if (abs(sum(composite_with_missing$weights_used) - 1) > 1e-9) {
    stop("Composite reweighting failed: rescaled weights do not sum to 1 after excluding a missing component.")
  }
  if (abs(composite_with_missing$score - 50) > 1e-9) {
    stop("Composite reweighting failed: expected 50 when all available components are 50, got ", composite_with_missing$score)
  }
  if (!identical(composite_with_missing$excluded, "queue_age")) {
    stop("Composite reweighting failed: expected 'queue_age' to be reported as excluded.")
  }

  invisible(TRUE)
}

# --- Orchestration ----------------------------------------------------------

#' Read the two persisted inputs this score depends on.
read_risk_score_inputs <- function() {
  metrics <- readr::read_csv("data/processed/analysis_metrics.csv", show_col_types = FALSE)
  berkeley_lab <- readr::read_csv("data/processed/queued_up_clean.csv", show_col_types = FALSE)
  list(metrics = metrics, berkeley_lab = berkeley_lab)
}

#' Pull a single metric's value out of the long-format analysis_metrics
#' tibble by name. Returns NA (not an error) if the metric's own value
#' was already NA in that file -- this function does not re-decide
#' validity, it just carries through what 04_metrics.R already determined.
extract_metric_value <- function(metrics, name) {
  row <- dplyr::filter(metrics, metric_name == name)
  if (nrow(row) != 1) {
    stop("Expected exactly one '", name, "' row in analysis_metrics.csv, found ", nrow(row))
  }
  row$value[[1]]
}

#' Build the final one-row Procurement Risk Score table.
#'
#' @return A one-row tibble with: geography, time_period, as_of_date,
#'   every raw component value, every normalized 0-100 score, the final
#'   composite score, which components (if any) were excluded, the
#'   weights actually used, the queue-age sample size, and a
#'   methodology_note.
build_risk_score_table <- function(metrics, berkeley_lab) {
  geography <- unique(metrics$geography)[[1]]
  time_period <- unique(metrics$time_period)[[1]]
  as_of_date <- unique(metrics$as_of_date)[[1]]

  raw_demand_pressure_ratio <- extract_metric_value(metrics, "Demand Pressure Ratio")
  raw_delivery_gap_mw <- extract_metric_value(metrics, "Delivery Gap MW")
  raw_queue_attrition_rate <- extract_metric_value(metrics, "Queue Attrition Rate")

  age_result <- compute_queue_age(berkeley_lab, as_of_date)
  raw_queue_age_days <- age_result$age_days

  normalized <- c(
    demand_pressure = normalize_demand_pressure(raw_demand_pressure_ratio),
    delivery_gap    = normalize_delivery_gap(raw_delivery_gap_mw),
    queue_attrition = normalize_attrition(raw_queue_attrition_rate),
    queue_age       = normalize_queue_age(raw_queue_age_days)
  )

  composite <- compute_composite_score(normalized, RISK_SCORE_WEIGHTS)

  weights_used_str <- paste(
    sprintf("%s=%.4f", names(composite$weights_used), composite$weights_used),
    collapse = "; "
  )
  excluded_str <- if (length(composite$excluded) == 0) {
    NA_character_
  } else {
    paste(composite$excluded, collapse = "; ")
  }

  methodology_note <- paste(
    "Weighting scheme (of total, before any exclusion):",
    "demand_pressure=1/6, delivery_gap=1/6, queue_attrition=1/3, queue_age=1/3",
    "(demand_pressure and delivery_gap are mathematically redundant --",
    "same two inputs, ratio vs. difference -- so together they count as",
    "one component's worth of weight, per docs/risk_score_design.md).",
    "Normalization for demand_pressure/delivery_gap/queue_age uses",
    "PROVISIONAL, arbitrary reference thresholds (see code comments in",
    "R/05_risk_score.R) -- there is only one snapshot observation, so no",
    "empirical distribution exists yet to calibrate against; queue_attrition",
    "is a true [0,1] proportion, not provisional. If any component is",
    "missing/non-finite for a given run, it is excluded and remaining",
    "weights are rescaled to sum to 1 (see excluded_components column).",
    "Interconnection queue MW is NOT deliverable MW -- every component",
    "here reflects potential capacity currently in the queue, not",
    "guaranteed future generation."
  )

  tibble::tibble(
    # Named `geography`, not `region`, to match the column name used in
    # every upstream processed file (integrated_analysis.csv,
    # analysis_metrics.csv) -- keeps this file joinable/consistent with
    # the rest of the pipeline rather than silently diverging.
    geography = geography,
    time_period = time_period,
    as_of_date = as_of_date,
    raw_demand_pressure_ratio = raw_demand_pressure_ratio,
    raw_delivery_gap_mw = raw_delivery_gap_mw,
    raw_queue_attrition_rate = raw_queue_attrition_rate,
    raw_queue_age_days = raw_queue_age_days,
    n_active_projects_for_queue_age = age_result$n_projects,
    norm_demand_pressure = normalized[["demand_pressure"]],
    norm_delivery_gap = normalized[["delivery_gap"]],
    norm_queue_attrition = normalized[["queue_attrition"]],
    norm_queue_age = normalized[["queue_age"]],
    procurement_risk_score = composite$score,
    excluded_components = excluded_str,
    weights_used = weights_used_str,
    methodology_note = methodology_note
  )
}

#' Run the full risk-score pipeline end to end: self-validate, read
#' inputs, compute, and write. Writes ONLY
#' data/processed/procurement_risk_scores.csv -- never touches any
#' earlier processed file.
#'
#' @return The one-row risk-score tibble (also written to disk).
run_risk_score_pipeline <- function() {
  validate_risk_score_functions()

  inputs <- read_risk_score_inputs()
  risk_score <- build_risk_score_table(inputs$metrics, inputs$berkeley_lab)

  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(risk_score, "data/processed/procurement_risk_scores.csv")

  risk_score
}

result <- run_risk_score_pipeline()
print(result)
