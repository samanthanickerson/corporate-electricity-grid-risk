# Sensitivity analysis for the Procurement Risk Score (R/05_risk_score.R).
#
# SCOPE, confirmed with Samantha 2026-08-24: the pipeline currently has
# exactly ONE region (ERCOT) and ONE snapshot -- ranking regions,
# identifying a "top 10," computing rank correlation between scenarios,
# and comparing across time periods are all undefined at n=1 (there is
# nothing to rank or correlate against). This script instead compares
# ERCOT's single composite score across 3 weighting scenarios and
# identifies which component drives each scenario's difference from the
# base case -- a real, honest sensitivity analysis of one score, not a
# ranking. See docs/risk_score_sensitivity_interpretation.md for the
# write-up, including what isn't answerable yet and why.
#
# Reads data/processed/analysis_metrics.csv and
# data/processed/queued_up_clean.csv (same inputs as R/05_risk_score.R).
# Writes ONLY output/analysis/risk_score_sensitivity.csv and
# output/figures/risk_score_sensitivity.png -- does not read, modify, or
# overwrite data/processed/procurement_risk_scores.csv or any other
# earlier file.
#
# HARD GUARDRAIL (CLAUDE.md, carried through every prior script this
# session): interconnection queue MW is NOT deliverable MW. The
# Procurement Risk Score is an analytical indicator, not objective
# truth -- this script exists specifically to demonstrate that, by
# showing how much the score moves under different defensible weighting
# choices.

library(dplyr)
library(tibble)
library(readr)
library(ggplot2)

# ---------------------------------------------------------------------
# Functions duplicated from R/05_risk_score.R (weighted_median,
# clip_0_100, compute_queue_age, the four normalize_* functions,
# compute_composite_score, extract_metric_value). Kept as exact copies
# rather than source()-ing 05_risk_score.R directly, which would also
# re-trigger that script's own pipeline run and CSV write as a side
# effect (its bottom-level statements aren't guarded against being
# sourced) -- matches this project's existing convention of each
# numbered script being self-contained (01->03->04->05 each read prior
# CSVs, never source()d a prior script).
#
# IMPORTANT: if the scoring methodology in R/05_risk_score.R ever
# changes (a different normalization range, a different composite-score
# formula), these copies must be updated identically, or this script's
# "base case" will silently stop matching the actual base case.
#
# FLAGGED 2026-08-26 (docs/decisions.md): R/04_metrics.R's Demand
# Pressure Ratio and Delivery Gap MW switched from an active_queue_mw
# base to a total_queue_mw base. The raw values these normalize_*
# functions receive (via extract_metric_value() below, reading
# analysis_metrics.csv directly -- the same file R/05 reads, so both
# scripts see the identical new values automatically) are now on a
# different scale: Demand Pressure Ratio roughly 1.03 -> 0.53, and
# Delivery Gap MW roughly +13,400 -> -371,000 MW for the real snapshot
# (total_queue_mw >= active_queue_mw always, so the gap doesn't just
# shrink, it flips sign). normalize_demand_pressure()'s max_ref = 5.0 was
# never re-examined against this shift -- still an open item.
#
# FIXED 2026-08-26: normalize_delivery_gap()'s old linear +-200,000 MW
# clip was actively broken by the shift above (-371,000 MW overshot the
# floor outright, so clip_0_100() silently saturated it to exactly 0,
# destroying all magnitude information). Replaced with a sign-aware
# bounded transform (50 * (1 + tanh(x / scale)), scale = 200,000, reusing
# the old ceiling as the scale rather than inventing a new number) that
# approaches but never hard-clips to 0/100 -- see R/05_risk_score.R's
# fuller comment on this function for the full rationale
# (docs/risk_score_design.md originally recommended exactly this shape
# for this component). Both copies must stay identical, per the
# paragraph above.
# ---------------------------------------------------------------------

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

clip_0_100 <- function(x) {
  pmin(pmax(x, 0), 100)
}

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

extract_metric_value <- function(metrics, name) {
  row <- dplyr::filter(metrics, metric_name == name)
  if (nrow(row) != 1) {
    stop("Expected exactly one '", name, "' row in analysis_metrics.csv, found ", nrow(row))
  }
  row$value[[1]]
}

# ---------------------------------------------------------------------
# Sensitivity-analysis-specific logic
# ---------------------------------------------------------------------

#' Three weighting scenarios, each summing to 1.0. The redundant pair
#' (demand_pressure, delivery_gap) is kept split evenly within their
#' combined "demand-side" share in every scenario -- isolates the one
#' thing actually being varied (demand-side emphasis vs. queue-side
#' emphasis) rather than introducing a second axis of variation.
#'
#' base_case matches RISK_SCORE_WEIGHTS in R/05_risk_score.R exactly
#' (demand-side 33.3% combined, queue-side 66.7% combined -- queue-side
#' is already weighted higher than demand-side in the base case, since
#' it has two non-redundant full-weight components).
SENSITIVITY_SCENARIOS <- list(
  base_case = c(
    demand_pressure = 1 / 6, delivery_gap = 1 / 6,
    queue_attrition = 1 / 3, queue_age = 1 / 3
  ),
  demand_pressure_heavy = c(
    demand_pressure = 0.30, delivery_gap = 0.30,
    queue_attrition = 0.20, queue_age = 0.20
  ),
  queue_risk_heavy = c(
    demand_pressure = 0.10, delivery_gap = 0.10,
    queue_attrition = 0.40, queue_age = 0.40
  )
)

#' Run one weighting scenario against a fixed set of normalized (0-100)
#' component scores. Normalization itself doesn't depend on weights, so
#' the same `normalized` vector is reused across all three scenarios --
#' only the weights change.
#'
#' @param normalized Named numeric vector of 0-100 scores.
#' @param weights One scenario's named weight vector from
#'   `SENSITIVITY_SCENARIOS`.
#' @return list(score, weights_used, excluded, weighted_contributions) --
#'   `weighted_contributions` is `normalized * weights_used`, per
#'   component, needed to identify what drives a difference from base.
run_scenario <- function(normalized, weights) {
  composite <- compute_composite_score(normalized, weights)
  weighted_contributions <- rep(NA_real_, length(normalized))
  names(weighted_contributions) <- names(normalized)
  used_names <- names(composite$weights_used)
  weighted_contributions[used_names] <- normalized[used_names] * composite$weights_used

  list(
    score = composite$score,
    weights_used = composite$weights_used,
    excluded = composite$excluded,
    weighted_contributions = weighted_contributions
  )
}

#' Identify which component's weighted contribution changed the most
#' (in absolute terms) between a scenario and the base case -- this is
#' what "compare rankings against the base case" becomes at n=1: not a
#' rank comparison (nothing to rank with one region), but a driver
#' attribution explaining *why* the score moved.
#'
#' A component excluded from the composite (NA weighted contribution)
#' is treated as contributing 0 for this comparison, not skipped
#' entirely -- it genuinely contributed nothing to that scenario's
#' weighted sum, so a component that goes from excluded to included (or
#' vice versa) between the scenario and base case is correctly visible
#' as a driver, rather than silently vanishing from consideration via a
#' plain finite-only diff (which would turn "excluded on one side" into
#' NA and drop it, even though that's arguably the largest possible
#' change for that component). Not reachable via this script's own
#' `run_sensitivity_pipeline()` today, since all three scenarios reuse
#' the same `normalized` vector and exclusion depends only on
#' `is.finite(normalized)`, not on weights -- but the function is
#' written to be correct generally, not just for today's specific call
#' pattern.
#'
#' @param scenario_result Output of `run_scenario()` for the scenario.
#' @param base_result Output of `run_scenario()` for `base_case`.
#' @return list(component = character or NA, contribution_change = numeric).
identify_primary_driver <- function(scenario_result, base_result) {
  scenario_contrib <- scenario_result$weighted_contributions
  base_contrib <- base_result$weighted_contributions

  scenario_filled <- ifelse(is.finite(scenario_contrib), scenario_contrib, 0)
  base_filled <- ifelse(is.finite(base_contrib), base_contrib, 0)
  diffs <- scenario_filled - base_filled
  names(diffs) <- names(scenario_contrib)

  if (length(diffs) == 0 || all(diffs == 0)) {
    return(list(component = NA_character_, contribution_change = NA_real_))
  }
  driver <- names(diffs)[which.max(abs(diffs))]
  list(component = driver, contribution_change = diffs[[driver]])
}

#' Build the sensitivity-analysis table: one row per scenario.
#'
#' @param normalized Named numeric vector of 0-100 component scores
#'   (identical inputs across all scenarios).
#' @param geography,time_period,as_of_date Carried over from
#'   `analysis_metrics.csv` for context.
#' @return A tibble with one row per scenario in `SENSITIVITY_SCENARIOS`.
build_sensitivity_table <- function(normalized, geography, time_period, as_of_date) {
  scenario_results <- lapply(SENSITIVITY_SCENARIOS, run_scenario, normalized = normalized)
  base_result <- scenario_results[["base_case"]]

  methodology_note <- paste(
    "This is an ANALYTICAL INDICATOR, not objective truth -- the",
    "Procurement Risk Score's composite value depends on the weighting",
    "scheme chosen, demonstrated directly by how much it moves across",
    "these three defensible-but-different weightings. Scope: ERCOT",
    "only, one snapshot -- ranking regions, a 'top 10,' rank correlation",
    "between scenarios, and comparison across time periods are not",
    "meaningful yet (n=1 on both axes); see",
    "docs/risk_score_sensitivity_interpretation.md. Interconnection",
    "queue MW is NOT deliverable MW."
  )

  scenario_rows <- lapply(names(SENSITIVITY_SCENARIOS), function(scenario_name) {
    result <- scenario_results[[scenario_name]]
    driver <- identify_primary_driver(result, base_result)
    weights <- SENSITIVITY_SCENARIOS[[scenario_name]]

    tibble::tibble(
      geography = geography,
      time_period = time_period,
      as_of_date = as_of_date,
      scenario = scenario_name,
      weight_demand_pressure = weights[["demand_pressure"]],
      weight_delivery_gap = weights[["delivery_gap"]],
      weight_queue_attrition = weights[["queue_attrition"]],
      weight_queue_age = weights[["queue_age"]],
      norm_demand_pressure = normalized[["demand_pressure"]],
      norm_delivery_gap = normalized[["delivery_gap"]],
      norm_queue_attrition = normalized[["queue_attrition"]],
      norm_queue_age = normalized[["queue_age"]],
      procurement_risk_score = result$score,
      score_vs_base = if (scenario_name == "base_case") 0 else result$score - base_result$score,
      excluded_components = if (length(result$excluded) == 0) NA_character_ else paste(result$excluded, collapse = "; "),
      primary_driver = if (scenario_name == "base_case") NA_character_ else driver$component,
      primary_driver_contribution_change = if (scenario_name == "base_case") NA_real_ else driver$contribution_change,
      methodology_note = methodology_note
    )
  })

  dplyr::bind_rows(scenario_rows)
}

#' Build the comparison bar chart: one bar per scenario, with a
#' horizontal reference line at the base case's score. Scope is stated
#' plainly in the subtitle -- one region, one snapshot -- so the chart
#' can't be misread as a multi-region or multi-period comparison.
#'
#' @param sensitivity_table Output of `build_sensitivity_table()`.
#' @return A ggplot object.
build_sensitivity_chart <- function(sensitivity_table) {
  plot_data <- sensitivity_table %>%
    dplyr::mutate(
      scenario_label = dplyr::case_when(
        scenario == "base_case" ~ "Base case",
        scenario == "demand_pressure_heavy" ~ "Demand-pressure-heavy",
        scenario == "queue_risk_heavy" ~ "Queue-risk-heavy",
        TRUE ~ scenario
      )
    )
  base_score <- plot_data$procurement_risk_score[plot_data$scenario == "base_case"][[1]]
  as_of_date <- plot_data$as_of_date[[1]]

  ggplot2::ggplot(plot_data, ggplot2::aes(x = scenario_label, y = procurement_risk_score)) +
    ggplot2::geom_col(fill = "#3b6ea5", width = 0.6) +
    ggplot2::geom_hline(yintercept = base_score, linetype = "dashed", color = "grey40") +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("%.1f", procurement_risk_score)),
      vjust = -0.5
    ) +
    ggplot2::scale_y_continuous(limits = c(0, 100)) +
    ggplot2::labs(
      title = "Procurement Risk Score under alternative weighting scenarios",
      subtitle = paste0(
        "ERCOT only, single snapshot (as_of_date: ", as_of_date, ") -- ",
        "an analytical indicator, not objective risk. Dashed line = base case."
      ),
      x = NULL,
      y = "Procurement Risk Score (0-100)"
    ) +
    ggplot2::theme_minimal()
}

#' Run the full sensitivity-analysis pipeline end to end: read inputs,
#' normalize once, run all three scenarios, write the table and chart.
#' Writes ONLY output/analysis/risk_score_sensitivity.csv and
#' output/figures/risk_score_sensitivity.png -- never touches
#' data/processed/procurement_risk_scores.csv or any other earlier file.
#'
#' @return The sensitivity tibble (also written to disk, alongside the chart).
run_sensitivity_pipeline <- function() {
  metrics <- readr::read_csv("data/processed/analysis_metrics.csv", show_col_types = FALSE)
  berkeley_lab <- readr::read_csv("data/processed/queued_up_clean.csv", show_col_types = FALSE)

  geography <- unique(metrics$geography)[[1]]
  time_period <- unique(metrics$time_period)[[1]]
  as_of_date <- unique(metrics$as_of_date)[[1]]

  raw_demand_pressure_ratio <- extract_metric_value(metrics, "Demand Pressure Ratio")
  raw_delivery_gap_mw <- extract_metric_value(metrics, "Delivery Gap MW")
  raw_queue_attrition_rate <- extract_metric_value(metrics, "Queue Attrition Rate")
  raw_queue_age_days <- compute_queue_age(berkeley_lab, as_of_date)$age_days

  normalized <- c(
    demand_pressure = normalize_demand_pressure(raw_demand_pressure_ratio),
    delivery_gap    = normalize_delivery_gap(raw_delivery_gap_mw),
    queue_attrition = normalize_attrition(raw_queue_attrition_rate),
    queue_age       = normalize_queue_age(raw_queue_age_days)
  )

  sensitivity_table <- build_sensitivity_table(normalized, geography, time_period, as_of_date)
  chart <- build_sensitivity_chart(sensitivity_table)

  dir.create("output/analysis", recursive = TRUE, showWarnings = FALSE)
  dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)

  readr::write_csv(sensitivity_table, "output/analysis/risk_score_sensitivity.csv")
  ggplot2::ggsave(
    "output/figures/risk_score_sensitivity.png",
    plot = chart, width = 7, height = 5, dpi = 150
  )

  sensitivity_table
}

result <- run_sensitivity_pipeline()
print(result)
