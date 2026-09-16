# Builds the 10 requested visualizations from the pipeline's validated
# analytical outputs. Read-only against every processed file -- writes
# no new CSVs, only PNGs to output/figures/.
#
# SCOPE, confirmed with Samantha via clarifying question (2026-08-24):
# `integrated_analysis.csv` / `analysis_metrics.csv` /
# `procurement_risk_scores.csv` are each exactly ONE row -- a single
# ERCOT snapshot (docs/decisions.md, 2026-08-19/20). Only Berkeley Lab's
# `q_date` (queue entry) and `wd_date` (withdrawal, ~64% populated) give
# real month-level history, and only on the SUPPLY side -- ERCOT Large
# Load's corporate demand figure has no historical dates at all.
# Charting demand, Demand Pressure Ratio, Delivery Gap MW, or the
# Procurement Risk Score "over time" would mean repeating today's one
# value across history -- a fabrication docs/decisions.md (2026-08-20)
# already flagged. So:
#   - REAL historical trends (from Berkeley Lab's actual dates): active
#     queue capacity over time, queue attrition over time, and the
#     month-over-month queue growth chart.
#   - SINGLE-SNAPSHOT indicators (never a fabricated trend line):
#     demand, demand pressure, delivery gap, risk score -- some
#     overlaid as a reference line/point on a real trend chart where
#     that's genuinely informative, never standing in for a history
#     that doesn't exist.
#   - Snapshot-only comparisons (no time dimension needed): risk score
#     component comparison, demand-vs-queue scatterplot.
#
# HARD GUARDRAIL (CLAUDE.md, carried through every prior script):
# interconnection queue MW is NOT deliverable MW. Every chart caption
# involving queue capacity reflects potential capacity currently in the
# queue, never guaranteed future generation.
#
# Per Samantha's explicit instruction, this script does NOT interpret
# the results -- charts only. A one-sentence-per-chart summary of what
# each is designed to answer is delivered separately in chat.

library(dplyr)
library(tibble)
library(readr)
library(purrr)
library(ggplot2)
library(scales)
library(stringr)

# --- Shared design system ---------------------------------------------

# Colorblind-safe (Okabe-Ito) palette, fixed to queue status categories
# everywhere they appear so the same status is always the same color
# across all 10 files.
STATUS_COLORS <- c(
  active      = "#0072B2",
  withdrawn   = "#D55E00",
  operational = "#009E73",
  suspended   = "#E69F00"
)
STATUS_LABELS <- c(
  active = "Active", withdrawn = "Withdrawn",
  operational = "Operational", suspended = "Suspended"
)

# Distinct colors for the four single-value indicators (demand,
# pressure, gap, score) -- deliberately not reusing STATUS_COLORS so a
# color never carries two different meanings across the chart set.
INDICATOR_COLORS <- c(
  demand = "#56B4E9", pressure = "#CC79A7",
  gap = "#666666", score = "#0072B2"
)

theme_project <- function() {
  ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 14),
      plot.subtitle = ggplot2::element_text(color = "grey30", size = 10.5),
      plot.caption = ggplot2::element_text(color = "grey45", size = 8, hjust = 0),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "bottom",
      legend.title = ggplot2::element_blank()
    )
}

#' ggplot2's plot.title/subtitle/caption never wrap on their own -- a
#' string longer than the plot's rendered width simply runs off the
#' edge (confirmed on this script's first real execution: several
#' subtitles and every long caption were silently truncated at the
#' panel boundary). `width` is chosen per chart based on its actual
#' `ggsave()` width in inches, not a single global guess.
wrap_text <- function(text, width) {
  stringr::str_wrap(text, width = width)
}

#' Save one chart as a high-resolution PNG to output/figures/.
save_figure <- function(plot, filename, width = 8, height = 5) {
  dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    file.path("output/figures", filename), plot = plot,
    width = width, height = height, dpi = 300, bg = "white"
  )
}

# --- Shared data-prep helpers -------------------------------------------

#' Bucket dated MW values into calendar months and compute a running
#' cumulative sum per `status` category, filling months with zero new
#' entries so the line is never linearly interpolated across a gap that
#' didn't actually grow. This is the single audited implementation
#' backing every "over time" chart in this script (items 2, 3, 5, and
#' 10 -- item 3 consumes item 2's output directly) -- a bug here would
#' otherwise need fixing independently at every call site.
#'
#' @param dates Date vector (e.g. q_date or wd_date).
#' @param mw Numeric vector, same length as `dates`.
#' @param status Character vector, same length, or NULL to treat every
#'   row as one category ("total").
#' @return tibble(month, status, monthly_mw, cumulative_mw), one row per
#'   month per status, spanning the full observed month range. Carries
#'   an `n_excluded_mw` attribute -- the count of rows with a real date
#'   and status but a non-positive/non-finite MW value, excluded from
#'   every sum below. Every caller reports this count in its chart
#'   caption rather than only some of them disclosing it.
build_monthly_cumulative <- function(dates, mw, status = NULL) {
  if (is.null(status)) status <- rep("total", length(dates))

  has_date_status <- !is.na(dates) & !is.na(status)
  valid_mw <- is.finite(mw) & mw > 0
  valid <- has_date_status & valid_mw
  n_excluded_mw <- sum(has_date_status & !valid_mw)

  dates <- dates[valid]
  mw <- mw[valid]
  status <- status[valid]

  if (length(dates) == 0) {
    result <- tibble::tibble(
      month = as.Date(character()), status = character(),
      monthly_mw = numeric(), cumulative_mw = numeric()
    )
    attr(result, "n_excluded_mw") <- n_excluded_mw
    return(result)
  }

  month <- as.Date(format(dates, "%Y-%m-01"))
  all_months <- seq(min(month), max(month), by = "month")
  statuses <- unique(status)

  grid <- dplyr::cross_join(
    tibble::tibble(month = all_months),
    tibble::tibble(status = statuses)
  )

  monthly <- tibble::tibble(month = month, status = status, mw = mw) %>%
    dplyr::group_by(month, status) %>%
    dplyr::summarise(monthly_mw = sum(mw), .groups = "drop")

  result <- grid %>%
    dplyr::left_join(monthly, by = c("month", "status")) %>%
    dplyr::mutate(monthly_mw = dplyr::if_else(is.na(monthly_mw), 0, monthly_mw)) %>%
    dplyr::arrange(status, month) %>%
    dplyr::group_by(status) %>%
    dplyr::mutate(cumulative_mw = cumsum(monthly_mw)) %>%
    dplyr::ungroup()

  attr(result, "n_excluded_mw") <- n_excluded_mw
  result
}

#' Self-test for build_monthly_cumulative() against a small hand-built
#' example: two "active" entries in January (one with mw=0, which must
#' be excluded), a February row with mw=0 (excluded, so February should
#' carry the January cumulative total forward unchanged), and a March
#' "withdrawn" entry. Same pattern as the validate_*() self-tests in
#' 04_metrics.R / 05_risk_score.R -- the first real check this helper
#' gets, since R hasn't executed in this environment. stop()s loudly on
#' any mismatch rather than writing charts from unverified logic.
validate_monthly_cumulative <- function() {
  dates <- as.Date(c("2020-01-15", "2020-01-20", "2020-03-05", "2020-02-10"))
  mw <- c(10, 5, 20, 0)
  status <- c("active", "active", "withdrawn", "active")

  result <- build_monthly_cumulative(dates, mw, status)

  active_cum <- result %>%
    dplyr::filter(status == "active") %>%
    dplyr::arrange(month) %>%
    dplyr::pull(cumulative_mw)
  expected_active_cum <- c(15, 15, 15)
  if (!isTRUE(all.equal(active_cum, expected_active_cum))) {
    stop(
      "build_monthly_cumulative validation failed for 'active': expected ",
      paste(expected_active_cum, collapse = ", "), " got ",
      paste(active_cum, collapse = ", ")
    )
  }

  withdrawn_cum <- result %>%
    dplyr::filter(status == "withdrawn") %>%
    dplyr::arrange(month) %>%
    dplyr::pull(cumulative_mw)
  expected_withdrawn_cum <- c(0, 0, 20)
  if (!isTRUE(all.equal(withdrawn_cum, expected_withdrawn_cum))) {
    stop(
      "build_monthly_cumulative validation failed for 'withdrawn': expected ",
      paste(expected_withdrawn_cum, collapse = ", "), " got ",
      paste(withdrawn_cum, collapse = ", ")
    )
  }

  invisible(TRUE)
}

#' Map each Berkeley Lab row to its single current status label, or NA
#' if none of the four flags are set (unknown status -- excluded from
#' status-split charts, never silently folded into another category).
derive_status_label <- function(berkeley_lab) {
  dplyr::case_when(
    berkeley_lab$is_active ~ "active",
    berkeley_lab$is_withdrawn ~ "withdrawn",
    berkeley_lab$is_operational ~ "operational",
    berkeley_lab$is_suspended ~ "suspended",
    TRUE ~ NA_character_
  )
}

#' Scope Berkeley Lab rows to the same "cumulative-entered" window the
#' rest of the pipeline uses (docs/decisions.md, 2026-08-19 "Refined"
#' entry: `q_date <= ERCOT_as_of_date`, re-derived from the live
#' `as_of_date` each run, never hardcoded). Every time-series chart in
#' this script applies this filter first, so their cumulative totals
#' reconcile with `integrated_analysis.csv` instead of silently running
#' past the snapshot the rest of the pipeline is anchored to.
filter_in_scope <- function(berkeley_lab, as_of_date) {
  dplyr::filter(berkeley_lab, !is.na(q_date), q_date <= as_of_date)
}

#' Monthly cumulative active queue capacity -- shared by charts 2 and 3
#' so both read from the one build_monthly_cumulative() call.
#'
#' @param in_scope Berkeley Lab rows already passed through
#'   filter_in_scope() -- computed once by the caller and threaded into
#'   this and the other in-scope-dependent chart builders, rather than
#'   each independently re-filtering the full table for the same
#'   `as_of_date`.
active_queue_monthly <- function(in_scope) {
  active_rows <- dplyr::filter(in_scope, is_active)
  build_monthly_cumulative(active_rows$q_date, active_rows$mw_1)
}

#' Shared demand-reference overlay (horizontal line + label) used by
#' both charts that overlay today's single demand value on a real
#' supply-side trend (items 3 and 10) -- one implementation so the two
#' can't silently drift in color/style. Guards both a missing/non-finite
#' `demand` and a missing/non-finite `x_pos` (the latter arises if the
#' trend data it's meant to sit inside has zero rows, e.g. min()/max()
#' on an empty Date vector) -- either case skips the overlay entirely
#' rather than silently rendering a broken "NA MW" label or a
#' dashed line with no visible anchor.
build_demand_reference_layers <- function(demand, x_pos, hjust) {
  if (is.na(demand) || !is.finite(demand) || is.na(x_pos)) {
    return(list())
  }
  list(
    ggplot2::geom_hline(yintercept = demand, linetype = "dashed", color = "grey20", linewidth = 0.85),
    ggplot2::annotate(
      "text", x = x_pos, y = demand,
      label = paste0("Current corporate demand: ", scales::comma(demand), " MW"),
      vjust = -0.6, hjust = hjust, size = 3.2, color = "grey20"
    )
  )
}

#' Generic single-current-value indicator chart, used for demand,
#' demand pressure, delivery gap, and the risk score -- items where the
#' pipeline has exactly one value and no historical series exists.
#' Renders an explicit "not available" placeholder instead of a bar
#' silently reduced to zero if `value` is NA/non-finite.
build_single_value_chart <- function(label, value, fill_color, title,
                                      subtitle, y_label, caption,
                                      value_format = function(v) scales::comma(v)) {
  # All 4 charts built with this helper share the same ~6in width.
  subtitle <- wrap_text(subtitle, width = 58)
  caption <- wrap_text(caption, width = 58)

  if (is.na(value) || !is.finite(value)) {
    return(
      ggplot2::ggplot() +
        ggplot2::annotate(
          "text", x = 0, y = 0,
          label = "Value not available for this snapshot\n(see upstream notes/excluded_components)",
          size = 4, color = "grey30"
        ) +
        ggplot2::theme_void() +
        ggplot2::labs(title = title, subtitle = subtitle, caption = caption)
    )
  }

  df <- tibble::tibble(label = label, value = value)
  ggplot2::ggplot(df, ggplot2::aes(x = label, y = value)) +
    ggplot2::geom_hline(yintercept = 0, color = "grey60", linewidth = 0.4) +
    ggplot2::geom_col(fill = fill_color, width = 0.4) +
    ggplot2::geom_text(
      ggplot2::aes(label = value_format(value)),
      vjust = if (value >= 0) -0.6 else 1.4, fontface = "bold"
    ) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.12, 0.15))) +
    ggplot2::labs(title = title, subtitle = subtitle, x = NULL, y = y_label, caption = caption) +
    theme_project()
}

# --- Per-visualization chart builders ------------------------------------

#' 1. Large-load corporate demand -- single current snapshot.
build_chart_demand_snapshot <- function(integrated) {
  build_single_value_chart(
    label = "Corporate demand\n(data center sector)",
    value = integrated$corporate_demand_mw[[1]],
    fill_color = INDICATOR_COLORS[["demand"]],
    title = "Large-Load Corporate Demand",
    subtitle = paste0(
      "Single current snapshot as of ", format(integrated$as_of_date[[1]], "%B %d, %Y"),
      " — ERCOT Large Load publishes no historical demand dates"
    ),
    y_label = "Demand (MW)",
    caption = "Source: ercotqueue.com Large Load queue summary, data_center sector. One observation, not a trend."
  )
}

#' 2. Active generation queue capacity over time -- real trend.
build_chart_active_queue_over_time <- function(monthly_active, as_of_date) {
  n_excluded <- attr(monthly_active, "n_excluded_mw")
  ggplot2::ggplot(monthly_active, ggplot2::aes(x = month, y = cumulative_mw)) +
    ggplot2::geom_line(color = STATUS_COLORS[["active"]], linewidth = 1) +
    ggplot2::scale_y_continuous(labels = scales::comma) +
    ggplot2::scale_x_date(date_breaks = "5 years", date_labels = "%Y") +
    ggplot2::labs(
      title = "Active Generation Queue Capacity Over Time",
      subtitle = wrap_text(paste0(
        "Cumulative MW of currently-active ERCOT interconnection requests, by month entered, ",
        "through ", format(as_of_date, "%B %Y")
      ), width = 84),
      x = "Queue entry date (month)", y = "Cumulative active queue capacity (MW)",
      caption = wrap_text(paste0(
        "Source: Berkeley Lab Queued Up, region == 'ERCOT', q_date <= as_of_date. ", n_excluded,
        " record(s) with a non-positive/missing MW value are excluded from this cumulative total. ",
        "Status reflects current standing, not historical status at each past date."
      ), width = 84)
    ) +
    theme_project()
}

#' 3. Corporate demand vs. active queue capacity over time -- real
#' supply-side trend with today's single demand value overlaid as a
#' reference line for visual comparison, never implying demand itself
#' had a history.
build_chart_demand_vs_active_queue <- function(monthly_active, integrated) {
  demand <- integrated$corporate_demand_mw[[1]]
  n_excluded <- attr(monthly_active, "n_excluded_mw")
  ggplot2::ggplot(monthly_active, ggplot2::aes(x = month, y = cumulative_mw)) +
    ggplot2::geom_line(color = STATUS_COLORS[["active"]], linewidth = 1) +
    build_demand_reference_layers(demand, x_pos = min(monthly_active$month), hjust = 0) +
    ggplot2::scale_y_continuous(labels = scales::comma) +
    ggplot2::scale_x_date(date_breaks = "5 years", date_labels = "%Y") +
    ggplot2::labs(
      title = "Corporate Demand vs. Active Queue Capacity Over Time",
      subtitle = wrap_text(paste0(
        "Active queue capacity's real growth history vs. current demand as of ",
        format(integrated$as_of_date[[1]], "%B %d, %Y")
      ), width = 84),
      x = "Queue entry date (month)", y = "MW",
      caption = wrap_text(paste0(
        "Demand is a single current snapshot overlaid for context — it does not itself have a ",
        "historical trend. ", n_excluded, " record(s) with a non-positive/missing MW value are ",
        "excluded from the active-queue line."
      ), width = 84)
    ) +
    theme_project()
}

#' 4. Demand Pressure Ratio -- single current snapshot. Uses
#' total_queue_mw as the base (2026-08-26 decision, docs/decisions.md),
#' not active_queue_mw -- distinct from charts 2/3/9, which legitimately
#' still show active-only capacity as their own separate view.
build_chart_demand_pressure_snapshot <- function(risk_score) {
  build_single_value_chart(
    label = "Demand Pressure Ratio",
    value = risk_score$raw_demand_pressure_ratio[[1]],
    fill_color = INDICATOR_COLORS[["pressure"]],
    title = "Demand Pressure Ratio",
    subtitle = paste0(
      "Single current snapshot as of ", format(risk_score$as_of_date[[1]], "%B %d, %Y"),
      " — corporate demand ÷ total queue capacity (everything ever entered)"
    ),
    y_label = "Ratio (demand / total queue MW)",
    caption = "No historical demand data exists to compute this ratio at past dates.",
    value_format = function(v) sprintf("%.2f×", v)
  )
}

#' 5. Queue attrition over time -- real trend, using actual withdrawal
#' event dates (wd_date), not queue-entry dates. `in_scope` is already
#' filtered to q_date <= as_of_date by the caller; further bounded here
#' to wd_date <= as_of_date so a withdrawal can't be plotted after the
#' snapshot this chart claims to run "through."
build_chart_queue_attrition_over_time <- function(in_scope, as_of_date) {
  withdrawn_in_scope <- dplyr::filter(in_scope, is_withdrawn)

  usable <- !is.na(withdrawn_in_scope$wd_date) & withdrawn_in_scope$wd_date <= as_of_date
  n_excluded_date <- sum(!usable)

  monthly <- build_monthly_cumulative(
    withdrawn_in_scope$wd_date[usable], withdrawn_in_scope$mw_1[usable]
  )
  n_excluded_mw <- attr(monthly, "n_excluded_mw")

  ggplot2::ggplot(monthly, ggplot2::aes(x = month, y = cumulative_mw)) +
    ggplot2::geom_line(color = STATUS_COLORS[["withdrawn"]], linewidth = 1) +
    ggplot2::scale_y_continuous(labels = scales::comma) +
    ggplot2::scale_x_date(date_breaks = "5 years", date_labels = "%Y") +
    ggplot2::labs(
      title = "Queue Attrition Over Time",
      subtitle = wrap_text(paste0(
        "Cumulative MW of withdrawn ERCOT interconnection requests, by month of actual withdrawal, ",
        "through ", format(as_of_date, "%B %Y")
      ), width = 84),
      x = "Withdrawal date (month)", y = "Cumulative withdrawn capacity (MW)",
      caption = wrap_text(paste0(
        "Source: Berkeley Lab Queued Up, region == 'ERCOT', q_date <= as_of_date. ", n_excluded_date,
        " withdrawn record(s) with a missing or after-as_of_date withdrawal date are excluded ",
        "(flagged, not silently dropped -- see flag_withdrawn_missing_wd_date). ", n_excluded_mw,
        " additional record(s) with a non-positive/missing MW value are also excluded."
      ), width = 84)
    ) +
    theme_project()
}

#' 6. Delivery Gap MW -- single current snapshot. Uses total_queue_mw as
#' the base (2026-08-26 decision, docs/decisions.md), not
#' active_queue_mw. Sign is meaningful (positive = demand exceeds total
#' supply; negative = total supply exceeds demand), so the shared
#' helper's zero reference line matters here in particular.
build_chart_delivery_gap_snapshot <- function(risk_score) {
  build_single_value_chart(
    label = "Delivery Gap",
    value = risk_score$raw_delivery_gap_mw[[1]],
    fill_color = INDICATOR_COLORS[["gap"]],
    title = "Delivery Gap MW",
    subtitle = paste0(
      "Single current snapshot as of ", format(risk_score$as_of_date[[1]], "%B %d, %Y"),
      " — corporate demand minus total queue capacity (everything ever entered)"
    ),
    y_label = "Gap (MW) — positive = demand exceeds total supply",
    caption = "Gap against POTENTIAL future generation capacity in the interconnection queue, NOT deliverable MW — queue MW is not deliverable MW."
  )
}

#' 7. Procurement Risk Score -- single current snapshot.
build_chart_risk_score_snapshot <- function(risk_score) {
  build_single_value_chart(
    label = "Procurement Risk Score",
    value = risk_score$procurement_risk_score[[1]],
    fill_color = INDICATOR_COLORS[["score"]],
    title = "Procurement Risk Score",
    subtitle = paste0(
      "Single current snapshot as of ", format(risk_score$as_of_date[[1]], "%B %d, %Y"),
      " — an analytical indicator, not objective risk"
    ),
    y_label = "Score (0–100)",
    caption = "Composite of provisional, weighted component scores (see docs/risk_score_design.md). Not a ranking, not objective truth.",
    value_format = function(v) sprintf("%.1f", v)
  )
}

#' 8. Risk score component comparison -- no time dimension; compares
#' the 4 normalized components of the current snapshot's score.
build_chart_component_comparison <- function(risk_score) {
  components <- tibble::tibble(
    component = c("Demand Pressure", "Delivery Gap", "Queue Attrition", "Queue Age"),
    normalized_score = c(
      risk_score$norm_demand_pressure[[1]], risk_score$norm_delivery_gap[[1]],
      risk_score$norm_queue_attrition[[1]], risk_score$norm_queue_age[[1]]
    )
  ) %>%
    dplyr::arrange(dplyr::desc(normalized_score)) %>%
    dplyr::mutate(
      component = factor(component, levels = component),
      # geom_text's y aesthetic would otherwise inherit normalized_score
      # (NA for an excluded component), and ggplot2 silently drops any
      # layer row with an NA required aesthetic -- so a missing
      # component's bar AND its "N/A" label would both vanish with no
      # visual trace, contradicting the caption below. label_y gives
      # the text layer its own always-finite position.
      label_y = dplyr::if_else(is.na(normalized_score), 3, normalized_score)
    )

  ggplot2::ggplot(components, ggplot2::aes(x = component, y = normalized_score)) +
    ggplot2::geom_col(fill = STATUS_COLORS[["active"]]) +
    ggplot2::geom_text(
      ggplot2::aes(y = label_y, label = ifelse(is.na(normalized_score), "N/A", sprintf("%.0f", normalized_score))),
      vjust = -0.6, fontface = "bold"
    ) +
    ggplot2::scale_y_continuous(limits = c(0, 100), expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::labs(
      title = "Procurement Risk Score — Component Comparison",
      subtitle = wrap_text(paste0(
        "Normalized (0–100) component scores for the current ERCOT snapshot (",
        format(risk_score$as_of_date[[1]], "%B %d, %Y"), ")"
      ), width = 66),
      x = NULL, y = "Normalized score (0–100, provisional thresholds)",
      caption = wrap_text(
        "Provisional normalization thresholds (docs/risk_score_design.md), not empirically calibrated. Missing components are excluded, not shown as 0.",
        width = 66
      )
    ) +
    theme_project()
}

#' 9. Demand vs. active queue capacity scatterplot with a 1:1 reference
#' line -- exactly one point, since there is exactly one snapshot.
#' Guards a missing demand or active-queue value the same way every
#' single-value chart does, rather than silently publishing a blank
#' plot with a caption that still claims "one point."
build_chart_demand_vs_queue_scatter <- function(integrated) {
  demand <- integrated$corporate_demand_mw[[1]]
  active_queue <- integrated$active_queue_mw[[1]]

  if (is.na(demand) || !is.finite(demand) || is.na(active_queue) || !is.finite(active_queue)) {
    return(
      ggplot2::ggplot() +
        ggplot2::annotate(
          "text", x = 0, y = 0,
          label = "Value not available for this snapshot\n(demand or active queue capacity is missing)",
          size = 4, color = "grey30"
        ) +
        ggplot2::theme_void() +
        ggplot2::labs(title = "Corporate Demand vs. Active Queue Capacity")
    )
  }

  max_val <- max(demand, active_queue) * 1.15

  ggplot2::ggplot(tibble::tibble(x = active_queue, y = demand), ggplot2::aes(x = x, y = y)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.7) +
    ggplot2::geom_point(color = STATUS_COLORS[["active"]], size = 5) +
    ggplot2::coord_equal(xlim = c(0, max_val), ylim = c(0, max_val)) +
    ggplot2::scale_x_continuous(labels = scales::comma) +
    ggplot2::scale_y_continuous(labels = scales::comma) +
    ggplot2::labs(
      title = "Corporate Demand vs. Active Queue Capacity",
      subtitle = wrap_text(paste0(
        "Single current observation as of ", format(integrated$as_of_date[[1]], "%B %d, %Y"),
        " — dashed line is 1:1 (demand = active queue capacity)"
      ), width = 58),
      x = "Active queue capacity (MW)", y = "Corporate demand (MW)",
      caption = wrap_text(
        "One point, one snapshot — not a distribution. Above the line: demand currently exceeds active supply in the queue.",
        width = 58
      )
    ) +
    theme_project()
}

#' 10. Month-over-month queue growth -- THE PRIMARY STORY CHART. Real
#' trend: cumulative Berkeley Lab ERCOT queue capacity by month
#' entered, stacked by current status, spanning the full observed
#' history, with today's demand overlaid as a reference line.
build_chart_queue_growth_primary <- function(in_scope, integrated) {
  as_of_date <- integrated$as_of_date[[1]]
  status <- derive_status_label(in_scope)
  n_excluded_status <- sum(is.na(status))
  monthly <- build_monthly_cumulative(in_scope$q_date, in_scope$mw_1, status) %>%
    dplyr::mutate(status = factor(status, levels = c("active", "withdrawn", "operational", "suspended")))
  n_excluded_mw <- attr(monthly, "n_excluded_mw")

  demand <- integrated$corporate_demand_mw[[1]]

  ggplot2::ggplot(monthly, ggplot2::aes(x = month, y = cumulative_mw, fill = status)) +
    ggplot2::geom_area(position = "stack", alpha = 0.9) +
    build_demand_reference_layers(demand, x_pos = max(monthly$month), hjust = 1) +
    ggplot2::scale_fill_manual(values = STATUS_COLORS, labels = STATUS_LABELS) +
    ggplot2::scale_y_continuous(labels = scales::comma) +
    ggplot2::scale_x_date(date_breaks = "5 years", date_labels = "%Y") +
    ggplot2::labs(
      title = "ERCOT Interconnection Queue Growth, Month by Month",
      subtitle = wrap_text(paste0(
        "Cumulative queue capacity by current status, through ",
        format(as_of_date, "%B %Y"), " — three decades of queue growth vs. today's demand"
      ), width = 100),
      x = "Queue entry date (month)", y = "Cumulative queue capacity (MW)",
      caption = wrap_text(paste0(
        "Source: Berkeley Lab Queued Up, region == 'ERCOT', q_date <= as_of_date. Status reflects each ",
        "project's current standing, not its historical status at each past date. ", n_excluded_status,
        " record(s) with an unknown/unrecorded status and ", n_excluded_mw,
        " record(s) with a non-positive/missing MW value are excluded from this cumulative total. ",
        "Demand is a single current snapshot overlaid for context, not a historical series."
      ), width = 100)
    ) +
    theme_project()
}

# --- Orchestration --------------------------------------------------------

#' Read the three inputs actually used by these 10 charts. Read-only --
#' no processed file is modified. analysis_metrics.csv and
#' output/analysis/risk_score_sensitivity.csv are not read here: every
#' value these charts need (raw components, normalized components, the
#' composite score) is already carried forward into
#' procurement_risk_scores.csv, so reading the upstream files again
#' would be a redundant, unused import.
read_visualization_inputs <- function() {
  list(
    berkeley_lab = readr::read_csv("data/processed/queued_up_clean.csv", show_col_types = FALSE),
    integrated = readr::read_csv("data/processed/integrated_analysis.csv", show_col_types = FALSE),
    risk_score = readr::read_csv("data/processed/procurement_risk_scores.csv", show_col_types = FALSE)
  )
}

#' Build and save all 10 visualizations. No interpretation here, per
#' Samantha's explicit instruction -- charts and their axis/caption text
#' only.
run_visualization_pipeline <- function() {
  validate_monthly_cumulative()

  inputs <- read_visualization_inputs()
  berkeley_lab <- inputs$berkeley_lab
  integrated <- inputs$integrated
  risk_score <- inputs$risk_score

  if (nrow(integrated) != 1) {
    stop("Expected exactly one row in integrated_analysis.csv (single snapshot), found ", nrow(integrated))
  }
  if (nrow(risk_score) != 1) {
    stop("Expected exactly one row in procurement_risk_scores.csv (single snapshot), found ", nrow(risk_score))
  }

  # Computed once and threaded into every chart that needs it, rather
  # than each independently re-filtering the full Berkeley Lab table
  # for the same as_of_date.
  as_of_date <- integrated$as_of_date[[1]]
  in_scope <- filter_in_scope(berkeley_lab, as_of_date)
  monthly_active <- active_queue_monthly(in_scope)

  charts <- list(
    large_load_demand_snapshot       = list(plot = build_chart_demand_snapshot(integrated), width = 6, height = 5),
    active_queue_capacity_over_time  = list(plot = build_chart_active_queue_over_time(monthly_active, as_of_date), width = 9, height = 5.5),
    demand_vs_active_queue_over_time = list(plot = build_chart_demand_vs_active_queue(monthly_active, integrated), width = 9, height = 5.5),
    demand_pressure_snapshot         = list(plot = build_chart_demand_pressure_snapshot(risk_score), width = 6, height = 5),
    queue_attrition_over_time        = list(plot = build_chart_queue_attrition_over_time(in_scope, as_of_date), width = 9, height = 5.5),
    delivery_gap_snapshot            = list(plot = build_chart_delivery_gap_snapshot(risk_score), width = 6, height = 5),
    procurement_risk_score_snapshot  = list(plot = build_chart_risk_score_snapshot(risk_score), width = 6, height = 5),
    risk_score_component_comparison  = list(plot = build_chart_component_comparison(risk_score), width = 7, height = 5.5),
    demand_vs_queue_scatter          = list(plot = build_chart_demand_vs_queue_scatter(integrated), width = 6, height = 6),
    queue_growth_month_over_month    = list(plot = build_chart_queue_growth_primary(in_scope, integrated), width = 11, height = 6.5)
  )

  purrr::iwalk(charts, function(entry, name) {
    save_figure(entry$plot, paste0(name, ".png"), width = entry$width, height = entry$height)
  })

  invisible(charts)
}

result <- run_visualization_pipeline()
message("Wrote ", length(result), " figures to output/figures/")
