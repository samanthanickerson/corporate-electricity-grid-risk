# Integrates the two source pipelines (ERCOT Large Load demand-side and
# Berkeley Lab "Queued Up" supply-side) into a single composite dataset,
# per the methodology fully decided in docs/decisions.md (2026-08-17,
# 2026-08-19). Reads only PERSISTED files from data/processed/ — this
# script does not re-fetch or re-clean anything itself, and does not
# share in-memory state with R/01_import_clean.R.
#
# Reads data/processed/ercot_large_load_queue_summary.csv, NOT
# data/processed/ercotqueue_clean.csv — the latter is derived from
# load_projects.json, whose sector aggregates come from a different,
# older snapshot tag than the as_of_date this integration anchors to
# (docs/decisions.md, 2026-08-19 "Refined" entry). Using it here would
# silently break the temporal alignment the whole design depends on.
#
# The integrated dataset is a SINGLE snapshot row, not a time series:
# ERCOT Large Load has exactly one as_of_date and no per-project
# historical dates, so there is no demand-side trend to build a series
# from. docs/decisions.md explicitly warns against framing this
# comparison as growth or change over time.

library(dplyr)
library(tibble)
library(readr)

INTEGRATION_METHODOLOGY_NOTE <- paste(
  "Two independently-aggregated ERCOT-wide totals, not a row-level join",
  "(Berkeley Lab is project-level, ERCOT Large Load is aggregate-only,",
  "with no shared key and no way to determine overlap between buckets).",
  "This is a snapshot of current state, not a trend -- ERCOT Large Load",
  "has no demand-side historical series, so this figure must never be",
  "read as growth or change over time. See docs/decisions.md,",
  "2026-08-17 and 2026-08-19."
)

#' Read the two persisted inputs this integration depends on.
#'
#' @return list(berkeley_lab = tibble, ercot_queue_summary = tibble)
read_integration_inputs <- function() {
  berkeley_lab <- readr::read_csv(
    "data/processed/queued_up_clean.csv",
    show_col_types = FALSE
  )
  ercot_queue_summary <- readr::read_csv(
    "data/processed/ercot_large_load_queue_summary.csv",
    show_col_types = FALSE
  )
  list(berkeley_lab = berkeley_lab, ercot_queue_summary = ercot_queue_summary)
}

#' Pull the single `as_of_date` and `data_center` demand figure this
#' integration anchors to. Both are asserted to be exactly one value —
#' the whole design depends on a single snapshot, so a source that ever
#' returns more than one should fail loudly here, not silently pick one.
#'
#' @param ercot_queue_summary Read back from
#'   `data/processed/ercot_large_load_queue_summary.csv`.
#' @return list(as_of_date = Date, corporate_demand_mw = numeric)
extract_demand_anchor <- function(ercot_queue_summary) {
  as_of_dates <- unique(ercot_queue_summary$as_of_date)
  if (length(as_of_dates) != 1) {
    stop(
      "Expected exactly one as_of_date in ercot_large_load_queue_summary.csv, found ",
      length(as_of_dates)
    )
  }

  data_center_rows <- ercot_queue_summary %>%
    dplyr::filter(dimension == "sector", sector == "data_center")
  if (nrow(data_center_rows) != 1) {
    stop(
      "Expected exactly one data_center sector row, found ",
      nrow(data_center_rows)
    )
  }

  list(
    as_of_date = as.Date(as_of_dates[[1]]),
    corporate_demand_mw = data_center_rows$mw[[1]]
  )
}

#' Map Berkeley Lab ERCOT rows against the `as_of_date` cutoff without
#' silently forcing anything into or out of scope. Every row lands in
#' exactly one of three named, counted buckets: `in_scope` (has a
#' `q_date` on or before `as_of_date` — decisions.md's "cumulative-
#' entered" definition), `unmatched_missing_date` (no `q_date` at all —
#' cannot be evaluated against the cutoff), or `unmatched_future_date`
#' (a `q_date` after `as_of_date` — not yet entered the queue as of this
#' snapshot).
#'
#' @param berkeley_lab Output of `read_integration_inputs()$berkeley_lab`.
#' @param as_of_date The single as_of_date from `extract_demand_anchor()`.
#' @return list(in_scope, unmatched_missing_date, unmatched_future_date)
map_berkeley_lab_to_time_period <- function(berkeley_lab, as_of_date) {
  list(
    in_scope = dplyr::filter(berkeley_lab, !is.na(q_date) & q_date <= as_of_date),
    unmatched_missing_date = dplyr::filter(berkeley_lab, is.na(q_date)),
    unmatched_future_date = dplyr::filter(berkeley_lab, !is.na(q_date) & q_date > as_of_date)
  )
}

#' Build the single-row integrated dataset.
#'
#' `active_queue_mw`/`withdrawn_queue_mw` are the two breakdowns
#' explicitly requested; `operational_queue_mw`/`suspended_queue_mw`
#' follow the same pattern from flags this project already built for
#' exactly this kind of later slicing (per "preserve source status
#' information so I can define the analytical subset later").
#'
#' @param in_scope Berkeley Lab rows with `q_date <= as_of_date`.
#' @param as_of_date The snapshot anchor date.
#' @param corporate_demand_mw The `data_center` demand figure.
#' @return A one-row tibble.
build_integrated_analysis <- function(in_scope, as_of_date, corporate_demand_mw) {
  tibble::tibble(
    geography = "ERCOT",
    time_period = paste0(
      "Cumulative entries through ", as_of_date,
      " (ERCOT Large Load as_of_date)"
    ),
    as_of_date = as_of_date,
    corporate_demand_mw = corporate_demand_mw,
    total_queue_mw = sum(in_scope$mw_1, na.rm = TRUE),
    active_queue_mw = sum(in_scope$mw_1[in_scope$is_active], na.rm = TRUE),
    withdrawn_queue_mw = sum(in_scope$mw_1[in_scope$is_withdrawn], na.rm = TRUE),
    operational_queue_mw = sum(in_scope$mw_1[in_scope$is_operational], na.rm = TRUE),
    suspended_queue_mw = sum(in_scope$mw_1[in_scope$is_suspended], na.rm = TRUE),
    n_projects_in_scope = nrow(in_scope),
    methodology_note = INTEGRATION_METHODOLOGY_NOTE
  )
}

#' Build the reconciliation report: source totals, aggregated totals,
#' unmatched records, unmapped capacity, and discrepancies — long format
#' (section, field, metric, value), matching the shape used by both
#' source pipelines' quality reports.
#'
#' @param berkeley_lab Full Berkeley Lab ERCOT tibble (pre-time-filter).
#' @param mapped Output of `map_berkeley_lab_to_time_period()`.
#' @param integrated The one-row tibble from `build_integrated_analysis()`.
#' @param corporate_demand_mw The `data_center` demand figure.
#' @return A tibble with columns: section, field, metric, value.
build_integration_reconciliation_report <- function(berkeley_lab, mapped, integrated, corporate_demand_mw) {
  source_totals <- tibble::tibble(
    section = "source_totals",
    field = c("berkeley_lab_ercot_rows", "berkeley_lab_ercot_mw_1", "ercot_large_load_data_center_mw"),
    metric = "value",
    value = as.character(c(
      nrow(berkeley_lab),
      sum(berkeley_lab$mw_1, na.rm = TRUE),
      corporate_demand_mw
    ))
  )

  aggregated_totals <- tibble::tibble(
    section = "aggregated_totals",
    field = c(
      "n_projects_in_scope", "total_queue_mw", "active_queue_mw",
      "withdrawn_queue_mw", "operational_queue_mw", "suspended_queue_mw",
      "corporate_demand_mw"
    ),
    metric = "value",
    value = as.character(c(
      integrated$n_projects_in_scope, integrated$total_queue_mw,
      integrated$active_queue_mw, integrated$withdrawn_queue_mw,
      integrated$operational_queue_mw, integrated$suspended_queue_mw,
      integrated$corporate_demand_mw
    ))
  )

  unmatched_records <- tibble::tibble(
    section = "unmatched_records",
    field = c("missing_q_date", "future_q_date"),
    metric = "n_rows",
    value = as.character(c(
      nrow(mapped$unmatched_missing_date),
      nrow(mapped$unmatched_future_date)
    ))
  )

  unmapped_capacity <- tibble::tibble(
    section = "unmapped_capacity",
    field = c("missing_q_date", "future_q_date"),
    metric = "mw_1_sum",
    value = as.character(c(
      sum(mapped$unmatched_missing_date$mw_1, na.rm = TRUE),
      sum(mapped$unmatched_future_date$mw_1, na.rm = TRUE)
    ))
  )

  # Two independent reconciliation checks (rows and MW) — both should
  # come out at (or very near) zero. A nonzero value here means the
  # accounting above missed something and should be investigated before
  # trusting the integrated dataset, not silently accepted.
  row_count_check <- nrow(berkeley_lab) -
    nrow(mapped$in_scope) - nrow(mapped$unmatched_missing_date) - nrow(mapped$unmatched_future_date)
  mw_check <- sum(berkeley_lab$mw_1, na.rm = TRUE) -
    integrated$total_queue_mw -
    sum(mapped$unmatched_missing_date$mw_1, na.rm = TRUE) -
    sum(mapped$unmatched_future_date$mw_1, na.rm = TRUE)

  discrepancies <- tibble::tibble(
    section = "discrepancies",
    field = c("berkeley_lab_row_count_reconciliation", "berkeley_lab_mw_1_reconciliation"),
    metric = c(
      "source_rows_minus_in_scope_minus_unmatched",
      "source_mw_minus_aggregated_minus_unmapped"
    ),
    value = as.character(c(row_count_check, mw_check))
  )

  dplyr::bind_rows(source_totals, aggregated_totals, unmatched_records, unmapped_capacity, discrepancies)
}

#' Run the full integration end to end: read inputs, extract the
#' temporal anchor, map Berkeley Lab rows against it without silently
#' forcing any into scope, build the integrated dataset and its
#' reconciliation report, and write both to disk.
#'
#' @return list(integrated, reconciliation_report) — also written to
#'   `data/processed/integrated_analysis.csv` and
#'   `output/analysis/integration_reconciliation.csv`.
run_data_integration <- function() {
  inputs <- read_integration_inputs()
  anchor <- extract_demand_anchor(inputs$ercot_queue_summary)
  mapped <- map_berkeley_lab_to_time_period(inputs$berkeley_lab, anchor$as_of_date)

  integrated <- build_integrated_analysis(
    mapped$in_scope, anchor$as_of_date, anchor$corporate_demand_mw
  )
  reconciliation_report <- build_integration_reconciliation_report(
    inputs$berkeley_lab, mapped, integrated, anchor$corporate_demand_mw
  )

  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  dir.create("output/analysis", recursive = TRUE, showWarnings = FALSE)

  readr::write_csv(integrated, "data/processed/integrated_analysis.csv")
  readr::write_csv(reconciliation_report, "output/analysis/integration_reconciliation.csv")

  list(integrated = integrated, reconciliation_report = reconciliation_report)
}

result <- run_data_integration()
print(result$integrated)
print(result$reconciliation_report)
