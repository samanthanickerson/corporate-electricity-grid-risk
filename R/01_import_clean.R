# Fetches ERCOT Large Load interconnection queue data from ercotqueue.com,
# an independent third-party tracker (not ercot.com itself), and parses
# the queue summary into a tidy table.
#
# Source: https://www.ercotqueue.com — License: CC BY 4.0
#   (https://creativecommons.org/licenses/by/4.0/)
# Underlying primary source: ERCOT Large Load Working Group (LLWG)
#   "Large Load Interconnection Status Update" reports (PPTX). ercotqueue.com
#   cites the specific report/slide for each figure in its own JSON `notes`
#   fields, which are preserved below in `source_citation`.
# robots.txt on ercotqueue.com allows "/data/load/" (checked 2026-08-17;
# only "/memo" is disallowed).

library(httr)
library(jsonlite)
library(dplyr)
library(tibble)
library(purrr)
library(readr)
library(readxl)
library(stringr)

ERCOT_LARGE_LOAD_RAW_DIR <- "data/raw/ercot_large_load"

ERCOT_LARGE_LOAD_URLS <- c(
  load_queue_summary = "https://www.ercotqueue.com/data/load/load_queue_summary.json",
  load_projects      = "https://www.ercotqueue.com/data/load/load_projects.json"
)

# Controlled vocabulary for load_projects.json's `sector` field. "other"
# doesn't appear in load_projects.json today but does in
# load_queue_summary.json's by_sector breakdown, so it's included here as
# a valid-but-currently-unobserved level rather than added ad hoc later.
LOAD_PROJECTS_SECTOR_LEVELS <- c("data_center", "crypto", "industrial", "mixed", "other")

# Shared verbatim attribution, used by every function below that builds a
# `source_citation` — kept in one place so a wording/URL correction can't
# drift out of sync between the load_queue_summary and load_projects paths.
ERCOTQUEUE_CITATION_PREFIX <- paste0(
  "ERCOTQueue.com (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/), ",
  "citing ERCOT Large Load Working Group (LLWG) 'Large Load Interconnection ",
  "Status Update' report. "
)

# Raw source files are immutable (`docs/decisions.md`, 2026-08-15), and
# ercotqueue.com is a LIVE endpoint whose `as_of_date` advances as ERCOT
# publishes new Large Load Working Group reports. An unconditional
# re-download therefore silently replaces the analysis input with a
# different snapshot, and `data/raw/` is gitignored, so the previous one is
# unrecoverable. Default to reusing what is already on disk.
#
# To deliberately pull a newer snapshot, run with
# `ERCOT_LARGE_LOAD_REFRESH = TRUE` — and expect every downstream figure to
# describe the new `as_of_date`, not the 2026-06-18 one the documentation
# quotes. A committed copy of the 2026-06-18 files is kept at
# `data/raw/ercot_large_load/snapshot_2026-06-18/`.
if (!exists("ERCOT_LARGE_LOAD_REFRESH")) {
  # `exists()` sees only R globals, so an environment variable set on the
  # command line (`ERCOT_LARGE_LOAD_REFRESH=TRUE Rscript R/01_import_clean.R`)
  # would otherwise be silently ignored -- and `Rscript` is the invocation
  # `README.md` documents.
  ERCOT_LARGE_LOAD_REFRESH <- toupper(
    Sys.getenv("ERCOT_LARGE_LOAD_REFRESH", "FALSE")
  ) %in% c("TRUE", "T", "1", "YES")
}

# The committed copy of the snapshot every published figure describes. A
# fresh clone has no `data/raw/` at all (it is gitignored), so without this
# the guard above would never fire and step 3 of README "Getting started"
# would download a live, newer snapshot -- silently recomputing every
# figure on a different `as_of_date`. Seeding from the committed copy makes
# the documented run reproduce the documented numbers.
ERCOT_LARGE_LOAD_SNAPSHOT_DIR <- file.path(
  ERCOT_LARGE_LOAD_RAW_DIR, "snapshot_2026-06-18"
)

#' Stop unless `path` holds parsable JSON.
#'
#' Guards the reuse path: `file.exists()` alone would happily accept a
#' truncated download or an HTTP error page saved as JSON, and with
#' re-downloading now off by default such a file would be cached
#' indefinitely rather than repaired by the next run.
#'
#' @param path File to check.
#' @return `invisible(TRUE)`; stops with an actionable message otherwise.
assert_parsable_json <- function(path) {
  ok <- tryCatch({
    jsonlite::fromJSON(path, simplifyVector = FALSE)
    TRUE
  }, error = function(e) FALSE)

  if (!ok) {
    stop(
      path, " is not parsable JSON -- it is most likely a truncated ",
      "download or a saved error page. Delete it and re-run, or re-run ",
      "with ERCOT_LARGE_LOAD_REFRESH=TRUE to replace it.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Fetch a JSON file over HTTP and save it byte-for-byte to disk.
#'
#' Does not overwrite an existing file unless `refresh = TRUE`; see the
#' comment above for why.
#'
#' @param url Source URL.
#' @param dest_dir Directory to save into (created if missing).
#' @param refresh Re-download even when the file already exists. Defaults
#'   to `ERCOT_LARGE_LOAD_REFRESH` (`FALSE`).
#' @return The local file path (invisibly).
fetch_and_save_json <- function(url,
                                dest_dir = ERCOT_LARGE_LOAD_RAW_DIR,
                                refresh = ERCOT_LARGE_LOAD_REFRESH) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest_path <- file.path(dest_dir, basename(url))

  snapshot_path <- file.path(ERCOT_LARGE_LOAD_SNAPSHOT_DIR, basename(url))

  if (!isTRUE(refresh)) {
    # Seed a fresh clone from the committed snapshot rather than the live
    # endpoint, so the documented run reproduces the documented figures.
    if (!file.exists(dest_path) && file.exists(snapshot_path)) {
      file.copy(snapshot_path, dest_path)
      message(
        "Seeded ", dest_path, " from the committed snapshot ",
        basename(ERCOT_LARGE_LOAD_SNAPSHOT_DIR),
        " (as_of_date 2026-06-18)."
      )
    }

    if (file.exists(dest_path)) {
      assert_parsable_json(dest_path)
      message(
        "Reusing existing raw file: ", dest_path,
        " (not re-downloading -- set ERCOT_LARGE_LOAD_REFRESH=TRUE to ",
        "pull a newer snapshot)."
      )
      return(invisible(dest_path))
    }
  }

  resp <- httr::GET(
    url,
    httr::user_agent("corporate-electricity-grid-risk research project")
  )
  httr::stop_for_status(resp, task = paste("fetch", url))

  if (file.exists(dest_path)) {
    warning(
      "Replacing ", dest_path, " with a fresh download. Every downstream ",
      "figure will describe the new as_of_date, not the 2026-06-18 one the ",
      "documentation quotes. (The 2026-06-18 files remain committed at ",
      ERCOT_LARGE_LOAD_SNAPSHOT_DIR, ".)",
      call. = FALSE
    )
  }

  # Write via a temp file so an interrupted or failed run cannot leave a
  # truncated file behind. Before the reuse guard existed, the next run
  # simply re-downloaded over any damage; now a bad file would be cached
  # indefinitely.
  tmp_path <- paste0(dest_path, ".part")
  on.exit(unlink(tmp_path), add = TRUE)
  writeBin(httr::content(resp, as = "raw"), tmp_path)
  assert_parsable_json(tmp_path)

  if (!file.rename(tmp_path, dest_path)) {
    stop("Failed to move ", tmp_path, " into place at ", dest_path, ".")
  }
  invisible(dest_path)
}

#' Fetch both ERCOT Large Load queue JSON files and save them raw.
#'
#' @param refresh Passed to `fetch_and_save_json()`.
#' @return Named character vector of local file paths, named
#'   `load_queue_summary` and `load_projects`.
fetch_ercot_large_load_data <- function(refresh = ERCOT_LARGE_LOAD_REFRESH) {
  vapply(
    ERCOT_LARGE_LOAD_URLS,
    fetch_and_save_json,
    FUN.VALUE = character(1),
    refresh = refresh
  )
}

#' Parse a saved load_queue_summary.json into a tidy long-format table.
#'
#' The source reports two independent breakdowns of the same total queue
#' (e.g. 466,497 MW as of the June 2026 snapshot): a status funnel
#' (`summary$buckets`) and a resource-sector split (`summary$by_sector`).
#' These are NOT a joint cross-tab in the source data — status and sector
#' are never reported together for the same MW figure — so this function
#' keeps them as separate rows (`dimension` distinguishes them) rather than
#' fabricating status-by-sector combinations that don't exist in the
#' source. Do not sum `mw` across both `dimension` values; that would
#' double-count the queue.
#'
#' Three status buckets (`planning_studies_approved`, `under_ercot_review`,
#' `no_studies_submitted`) have `mw = NA` because ERCOT's public LLWG
#' summary doesn't publish those internal-stage totals.
#'
#' @param json_path Path to a locally saved load_queue_summary.json.
#' @return A tibble with columns: dimension, status, sector, mw,
#'   project_count, as_of_date, source_citation.
parse_load_queue_summary <- function(json_path) {
  raw <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)
  s <- raw$summary

  as_row <- function(entry, dimension) {
    tibble::tibble(
      dimension = dimension,
      status = if (dimension == "status_funnel") entry$status else NA_character_,
      sector = if (dimension == "sector") entry$sector else NA_character_,
      mw = if (is.null(entry$mw)) NA_real_ else as.numeric(entry$mw),
      project_count = if (is.null(entry$project_count)) NA_integer_ else as.integer(entry$project_count),
      as_of_date = s$as_of_date,
      source_citation = paste0(ERCOTQUEUE_CITATION_PREFIX, entry$notes)
    )
  }

  dplyr::bind_rows(
    purrr::map_dfr(s$buckets, as_row, dimension = "status_funnel"),
    purrr::map_dfr(s$by_sector, as_row, dimension = "sector")
  )
}

#' Fetch, save, and parse the ERCOT Large Load queue data end to end.
#'
#' `queue_summary` is also written to
#' `data/processed/ercot_large_load_queue_summary.csv` — it carries the
#' `as_of_date` and `data_center` sector figure that
#' `R/03_data_integration.R` depends on, and that script reads persisted
#' files rather than sharing this function's in-memory return value.
#'
#' @param refresh Passed to `fetch_ercot_large_load_data()`. `FALSE` by
#'   default, so an existing raw snapshot is reused rather than replaced.
#' @return A list with `raw_paths` (both saved raw files) and
#'   `queue_summary` (the tidy tibble parsed from load_queue_summary.json).
import_ercot_large_load <- function(refresh = ERCOT_LARGE_LOAD_REFRESH) {
  raw_paths <- fetch_ercot_large_load_data(refresh = refresh)
  queue_summary <- parse_load_queue_summary(raw_paths[["load_queue_summary"]])

  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(queue_summary, "data/processed/ercot_large_load_queue_summary.csv")

  list(raw_paths = raw_paths, queue_summary = queue_summary)
}

# ---------------------------------------------------------------------
# load_projects.json cleaning pipeline
#
# load_projects.json is NOT a named project-level queue (see
# `docs/data_dictionary.md`) — it's 8 pre-aggregated `aggregate` /
# `anonymized_bucket` records. `county`, `load_zone`, `tsp`, `poi` are
# null in every published record because ERCOT doesn't publicly disclose
# that level of detail for large loads (see the source's own
# `confidentiality_note` field, and `docs/decisions.md`) — that's treated
# below as a documented, known limitation, not an error to fix.
# ---------------------------------------------------------------------

# NULL-safe scalar coercion — jsonlite returns NULL (not NA) for a
# missing JSON field when parsed with simplifyVector = FALSE.
to_chr <- function(x) if (is.null(x)) NA_character_ else as.character(x)
to_int <- function(x) if (is.null(x)) NA_integer_ else as.integer(x)

#' Flatten load_projects.json into one row per record.
#'
#' Field names are kept as ercotqueue.com defines them (matching
#' `docs/data_dictionary.md`), except `id` -> `record_id` (avoids R's
#' reserved-ish bare `id`). `record_type` is preserved rather than
#' treating all rows as equivalent, per the confidentiality note above.
#'
#' Date and MW fields are kept in two forms: an `_raw` character capture
#' of exactly what the source provided, and the parsed
#' (`as.Date`/`as.numeric`) value. Keeping both lets `validate_load_projects()`
#' distinguish "genuinely absent in source" (raw is NA) from "present but
#' failed to parse" (raw is not NA, parsed is) — collapsing straight to
#' the parsed value would silently lose that distinction.
#'
#' @param json_path Path to a locally saved load_projects.json.
#' @return A tibble, one row per source record.
flatten_load_projects <- function(json_path) {
  raw <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)

  as_row <- function(p) {
    tibble::tibble(
      record_id             = to_chr(p$id),
      record_type           = to_chr(p$record_type),
      status                = to_chr(p$status),
      sector                = to_chr(p$sector),
      requested_mw_raw      = to_chr(p$requested_mw),
      approved_mw_raw       = to_chr(p$approved_mw),
      observed_mw_raw       = to_chr(p$observed_mw),
      project_count         = to_int(p$project_count),
      county                = to_chr(p$county),
      load_zone             = to_chr(p$load_zone),
      tsp                   = to_chr(p$tsp),
      poi                   = to_chr(p$poi),
      last_seen_date_raw    = to_chr(p$last_seen_date),
      last_changed_date_raw = to_chr(p$last_changed_date),
      confidence            = to_chr(p$confidence),
      extraction_status     = to_chr(p$extraction_status),
      source_document_ids   = if (is.null(p$source_document_ids)) {
        NA_character_
      } else {
        paste(unlist(p$source_document_ids), collapse = "; ")
      },
      public_name           = to_chr(p$public_name),
      public_alias          = to_chr(p$public_alias),
      public_basis          = to_chr(p$public_basis),
      confidentiality_note  = to_chr(p$confidentiality_note)
    )
  }

  purrr::map_dfr(raw$projects, as_row) %>%
    dplyr::mutate(
      requested_mw      = suppressWarnings(as.numeric(requested_mw_raw)),
      approved_mw       = suppressWarnings(as.numeric(approved_mw_raw)),
      observed_mw       = suppressWarnings(as.numeric(observed_mw_raw)),
      last_seen_date    = as.Date(last_seen_date_raw),
      last_changed_date = as.Date(last_changed_date_raw),
      sector_std        = dplyr::if_else(
        sector %in% LOAD_PROJECTS_SECTOR_LEVELS, sector, NA_character_
      ),
      source_citation   = paste0(
        ERCOTQUEUE_CITATION_PREFIX,
        dplyr::coalesce(public_basis, "No public basis stated by source.")
      )
    )
}

#' Validate flattened load_projects rows without silently dropping any.
#'
#' Every row failing a check is routed to `excluded` with a documented
#' `exclusion_reason` rather than removed outright — per the project's
#' "never silently drop records" guardrail. Against the data inspected
#' while building this pipeline, 0 rows are expected to fail; these checks
#' exist to catch a future refresh with malformed data, not because
#' today's data is expected to need them.
#'
#' @param flat_tbl Output of `flatten_load_projects()`.
#' @return list(clean = tibble, excluded = tibble with `exclusion_reason`,
#'   checked = the full pre-filter tibble with `.invalid_*`/`.exclude`
#'   flag columns — passed on to `build_ercotqueue_quality_report()` so
#'   its counts are guaranteed to agree with what was actually excluded,
#'   rather than a second, separately-maintained copy of the same logic).
validate_load_projects <- function(flat_tbl) {
  checked <- flat_tbl %>%
    dplyr::mutate(
      .missing_id_or_type     = is.na(record_id) | is.na(record_type),
      .unexpected_record_type = !is.na(record_type) &
        !record_type %in% c("aggregate", "anonymized_bucket"),
      .invalid_last_seen      = !is.na(last_seen_date_raw) & is.na(last_seen_date),
      .invalid_last_changed   = !is.na(last_changed_date_raw) & is.na(last_changed_date),
      .invalid_requested_mw   = !is.na(requested_mw_raw) & is.na(requested_mw),
      .invalid_approved_mw    = !is.na(approved_mw_raw) & is.na(approved_mw),
      .invalid_observed_mw    = !is.na(observed_mw_raw) & is.na(observed_mw),
      .exclude = .missing_id_or_type | .unexpected_record_type | .invalid_last_seen |
        .invalid_last_changed | .invalid_requested_mw | .invalid_approved_mw |
        .invalid_observed_mw,
      exclusion_reason = dplyr::case_when(
        .missing_id_or_type     ~ "missing record_id or record_type",
        .unexpected_record_type ~ paste0("unexpected record_type: '", record_type, "'"),
        .invalid_last_seen      ~ paste0("unparseable last_seen_date: '", last_seen_date_raw, "'"),
        .invalid_last_changed   ~ paste0("unparseable last_changed_date: '", last_changed_date_raw, "'"),
        .invalid_requested_mw   ~ paste0("non-numeric requested_mw: '", requested_mw_raw, "'"),
        .invalid_approved_mw    ~ paste0("non-numeric approved_mw: '", approved_mw_raw, "'"),
        .invalid_observed_mw    ~ paste0("non-numeric observed_mw: '", observed_mw_raw, "'"),
        TRUE ~ NA_character_
      )
    )

  excluded <- dplyr::filter(checked, .exclude)

  clean <- checked %>%
    dplyr::filter(!.exclude) %>%
    dplyr::select(
      record_id, record_type, status, sector, sector_std,
      requested_mw, approved_mw, observed_mw, project_count,
      county, load_zone, tsp, poi,
      last_seen_date, last_changed_date,
      confidence, extraction_status, source_document_ids,
      public_name, public_alias, public_basis, confidentiality_note,
      source_citation
    )

  list(clean = clean, excluded = excluded, checked = checked)
}

#' Build a long-format data-quality report for the load_projects cleaning
#' pass: one row per metric, so row counts, the record_type breakdown,
#' per-field missingness, per-field invalid-value counts, and snapshot
#' coverage can share one table shape instead of forcing mismatched-shape
#' data into wide columns.
#'
#' Invalid-date/invalid-MW counts are read directly from the
#' `.invalid_*` flag columns `validate_load_projects()` already computed
#' (via `checked_tbl`) rather than recomputed here — recomputing the same
#' predicate in two places risks the two silently drifting apart if the
#' validation rule is ever changed in only one of them.
#'
#' @param checked_tbl `checked` element of `validate_load_projects()` —
#'   every row, pre-filter, with its `.invalid_*`/`.exclude` flags intact.
#' @param clean_tbl `clean` element of `validate_load_projects()`.
#' @param excluded_tbl `excluded` element of `validate_load_projects()`.
#' @return A tibble with columns: section, field, metric, value.
build_ercotqueue_quality_report <- function(checked_tbl, clean_tbl, excluded_tbl) {
  row_counts <- tibble::tibble(
    section = "row_counts",
    field = NA_character_,
    metric = c("rows_before_cleaning", "rows_after_cleaning", "rows_excluded"),
    value = as.character(c(nrow(checked_tbl), nrow(clean_tbl), nrow(excluded_tbl)))
  )

  record_type_counts <- clean_tbl %>%
    dplyr::count(record_type, name = "n") %>%
    dplyr::transmute(
      section = "record_type_counts",
      field = record_type,
      metric = "count",
      value = as.character(n)
    )

  missing_by_field <- purrr::imap_dfr(clean_tbl, function(col, name) {
    tibble::tibble(
      section = "missing_values",
      field = name,
      metric = "n_missing",
      value = as.character(sum(is.na(col)))
    )
  })

  invalid_dates <- tibble::tibble(
    section = "invalid_dates",
    field = c("last_seen_date", "last_changed_date"),
    metric = "n_invalid",
    value = as.character(c(
      sum(checked_tbl$.invalid_last_seen),
      sum(checked_tbl$.invalid_last_changed)
    ))
  )

  invalid_mw <- tibble::tibble(
    section = "invalid_mw",
    field = c("requested_mw", "approved_mw", "observed_mw"),
    metric = "n_invalid",
    value = as.character(c(
      sum(checked_tbl$.invalid_requested_mw),
      sum(checked_tbl$.invalid_approved_mw),
      sum(checked_tbl$.invalid_observed_mw)
    ))
  )

  # Surfaces a real caveat from docs/decisions.md (2026-08-19): these 8
  # records were captured across more than one ercotqueue.com refresh
  # (different `last_seen_date`/`last_changed_date` pairs), so the
  # cleaned CSV is not one consistent cross-section — this section makes
  # that visible in the artifact itself, not just in prose documentation.
  snapshot_coverage <- clean_tbl %>%
    dplyr::count(last_seen_date, last_changed_date, name = "n_records") %>%
    dplyr::transmute(
      section = "snapshot_coverage",
      field = paste0("last_seen=", last_seen_date, "; last_changed=", last_changed_date),
      metric = "n_records",
      value = as.character(n_records)
    )

  excluded_reasons <- if (nrow(excluded_tbl) == 0) {
    tibble::tibble(
      section = "excluded_records", field = NA_character_,
      metric = "count", value = "0"
    )
  } else {
    excluded_tbl %>%
      dplyr::transmute(
        section = "excluded_records", field = record_id,
        metric = "exclusion_reason", value = exclusion_reason
      )
  }

  dplyr::bind_rows(
    row_counts, record_type_counts, missing_by_field,
    invalid_dates, invalid_mw, snapshot_coverage, excluded_reasons
  )
}

#' Clean load_projects.json end to end: flatten, validate, and write both
#' the cleaned dataset and its data-quality report to disk.
#'
#' @param json_path Path to a locally saved load_projects.json.
#' @return list(clean, excluded, quality_report) — also written to
#'   `data/processed/ercotqueue_clean.csv` and
#'   `output/analysis/ercotqueue_quality_report.csv`.
clean_ercot_large_load_projects <- function(
  json_path = file.path(ERCOT_LARGE_LOAD_RAW_DIR, "load_projects.json")
) {
  raw_tbl <- flatten_load_projects(json_path)
  validated <- validate_load_projects(raw_tbl)
  quality_report <- build_ercotqueue_quality_report(
    validated$checked, validated$clean, validated$excluded
  )

  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  dir.create("output/analysis", recursive = TRUE, showWarnings = FALSE)

  readr::write_csv(validated$clean, "data/processed/ercotqueue_clean.csv")
  readr::write_csv(quality_report, "output/analysis/ercotqueue_quality_report.csv")

  list(clean = validated$clean, excluded = validated$excluded, quality_report = quality_report)
}

# ---------------------------------------------------------------------
# Berkeley Lab "Queued Up" cleaning pipeline (ERCOT subset)
#
# Generation-interconnection-queue data, row-per-project — structurally
# the opposite of the load_projects.json source above (that one is
# aggregate/bucketed; this one is 3,757 individual ERCOT-region rows, per
# docs/decisions.md, 2026-08-19). Filtered to region=='ERCOT', NEVER
# state=='TX' — docs/decisions.md (2026-08-17) documents these as
# genuinely non-interchangeable in BOTH directions: some state=='TX' rows
# sit outside ERCOT, and (confirmed 2026-08-20) some region=='ERCOT' rows
# have no state value at all.
#
# Interconnection queue MW (mw_1/mw_2/mw_3) is potential future
# generation capacity in the queue, not deliverable MW — same guardrail
# as the ERCOT Large Load section above. Nothing below renames these
# fields toward "capacity"/"deliverable" language, and q_status is never
# used to pre-filter rows: every row ships regardless of status, so
# Samantha can define her own analytical subset later from the
# `is_*`/`flag_*` columns rather than one baked into this pipeline.
# ---------------------------------------------------------------------

BERKELEY_LAB_RAW_DIR <- "data/raw/berkeley_lab"
BERKELEY_LAB_XLSX    <- file.path(BERKELEY_LAB_RAW_DIR, "Queued_Up_Data.xlsx")
BERKELEY_LAB_SHEET   <- "03. Complete Queue Data"

# Controlled vocabularies, quoted from the LBNL codebook via
# docs/data_dictionary.md, not inferred from what happens to appear in
# the ERCOT subset. "unknown" doesn't occur within ERCOT today (it's a
# file-wide value, 10 rows, all outside ERCOT) but is included as a
# valid-but-currently-unobserved level, same pattern as
# LOAD_PROJECTS_SECTOR_LEVELS's "other" above.
QUEUE_STATUS_LEVELS <- c("active", "withdrawn", "operational", "suspended", "unknown")
TYPE_1_LEVELS <- c(
  "Solar", "Wind", "Battery", "Gas", "Other", "Hydro", "Coal",
  "Offshore Wind", "Nuclear", "Geothermal", "Other Storage",
  "Diesel", "Oil", "Hydrogen"
)

#' Standardize a data frame's column names to snake_case, generically —
#' not a hardcoded rename list — so a future LBNL refresh that adds a
#' column or changes casing doesn't silently produce mismatched names
#' downstream. Against today's 30 columns this only changes
#' `IA_phase_raw`/`IA_phase_clean` -> `ia_phase_raw`/`ia_phase_clean`; the
#' other 28 are already snake_case and pass through unchanged.
standardize_bl_names <- function(df) {
  names(df) <- names(df) %>%
    stringr::str_trim() %>%
    stringr::str_replace_all("[^A-Za-z0-9]+", "_") %>%
    tolower() %>%
    stringr::str_replace_all("_+", "_") %>%
    stringr::str_remove_all("^_|_$")
  df
}

#' Read the raw "03. Complete Queue Data" sheet. There's a title row above
#' the real header (`skip = 1` is required, confirmed 2026-08-20 — reading
#' without it produces garbage `...1`-style column names). Uses readxl's
#' default type-guessing rather than forcing col_types = "text": this is
#' readxl's well-established standard behavior for date/numeric columns,
#' and safer than reading everything as text and re-parsing manually,
#' which would depend on unverified assumptions about how readxl renders
#' date-formatted cells in text mode (this pipeline is unexecuted in this
#' environment — R isn't installed here — so that behavior can't be
#' confirmed before shipping). The one confirmed bug in this source
#' (`fips_code` dropping leading zeros as a float) is fixed explicitly and
#' narrowly in `prepare_berkeley_lab_ercot()` instead of worked around by
#' changing how the whole sheet is read.
read_berkeley_lab_raw <- function(path = BERKELEY_LAB_XLSX, sheet = BERKELEY_LAB_SHEET) {
  readxl::read_excel(path, sheet = sheet, skip = 1) %>%
    standardize_bl_names()
}

#' Filter to region == 'ERCOT' and do the source-level type/format fixes
#' that apply regardless of q_status: date/MW/year columns coerced
#' explicitly (defensive — readxl already types them correctly, but this
#' makes the contract explicit rather than implicit), `fips_code` zero-
#' padded to 5 characters (the one confirmed bug in this source — doesn't
#' actually bite Texas rows, whose FIPS prefix 48 is already 5 digits, but
#' fixed generally rather than assumed safe), and character columns
#' trimmed with blank strings turned into real NA.
#'
#' @param raw_tbl Output of `read_berkeley_lab_raw()`.
#' @return list(ercot = tibble, n_total = int, n_ercot = int,
#'   n_region_missing = int) — the scope narrowing itself, including any
#'   rows with no `region` value at all, is returned alongside the data so
#'   it's documented in the quality report, not just silently applied.
prepare_berkeley_lab_ercot <- function(raw_tbl) {
  # Text columns (including region) are trimmed/blank-to-NA BEFORE the
  # ERCOT filter runs, not after — filtering on the raw, untrimmed column
  # would let a stray-whitespace "ERCOT " row miss the match, and
  # dplyr::filter(region == "ERCOT") treats an NA region exactly like a
  # non-match (silently dropped, indistinguishable from a genuine
  # non-ERCOT row) unless NA rows are counted separately first, below.
  normalized <- raw_tbl %>%
    dplyr::mutate(
      # tz = "UTC" is required, not cosmetic: readxl represents Excel
      # date cells as POSIXct at midnight UTC regardless of the
      # workbook's own timezone context. as.Date() on a POSIXct value
      # with no tz argument converts using the LOCAL system timezone —
      # on any machine set to a timezone behind UTC, that silently
      # shifts every date here back one day (docs/cleaning_code_review.md,
      # Finding 1.1). Explicit tz = "UTC" makes the conversion match what
      # the source cell actually says, independent of what machine runs
      # this script.
      dplyr::across(
        c(q_date, prop_date, on_date, wd_date, ia_date),
        ~ as.Date(.x, tz = "UTC")
      ),
      dplyr::across(c(mw_1, mw_2, mw_3), ~ suppressWarnings(as.numeric(.x))),
      dplyr::across(c(q_year, prop_year), ~ suppressWarnings(as.integer(.x))),
      # Guarded to the valid 5-digit FIPS range (0-99999) before the
      # integer coercion: a handful of non-ERCOT rows (confirmed on
      # first execution: 2 in NY, 1 in CA) carry corrupted values in
      # the billions -- look like two county codes concatenated with
      # no separator -- which overflow R's 32-bit integer range. These
      # never reach the ERCOT subset either way (filtered out below),
      # but the fix is applied here, before that filter, so it doesn't
      # depend on filter order to stay correct. The out-of-range value
      # is neutralized to NA_real_ BEFORE round()/as.integer() run --
      # dplyr::if_else() evaluates both of its branches eagerly across
      # the whole vector, so gating only the final if_else() (as a first
      # attempt at this fix did) still calls as.integer() on the huge
      # values and still throws the overflow warning even though the NA
      # branch is what actually gets selected.
      fips_code_numeric = suppressWarnings(as.numeric(fips_code)),
      fips_code_numeric = dplyr::if_else(
        is.na(fips_code_numeric) | fips_code_numeric < 0 | fips_code_numeric > 99999,
        NA_real_, fips_code_numeric
      ),
      fips_code = dplyr::if_else(
        is.na(fips_code_numeric), NA_character_,
        sprintf("%05d", as.integer(round(fips_code_numeric)))
      ),
      fips_code_numeric = NULL,
      dplyr::across(
        c(q_id, entity, q_status, ia_phase_raw, ia_phase_clean, county, state,
          poi_name, region, project_name, utility, developer, cluster, service,
          project_type, type_1, type_2, type_3, type_clean),
        ~ dplyr::na_if(stringr::str_trim(as.character(.x)), "")
      )
    )

  n_region_missing <- sum(is.na(normalized$region))
  ercot <- dplyr::filter(normalized, !is.na(region) & region == "ERCOT")

  list(
    ercot = ercot,
    n_total = nrow(raw_tbl),
    n_ercot = nrow(ercot),
    n_region_missing = n_region_missing
  )
}

#' Validate the prepared ERCOT rows without silently dropping any.
#'
#' Every row failing a check is routed to `excluded` with a documented
#' `exclusion_reason`, per the project's "never silently drop records"
#' guardrail. Checks are scoped to the fields a row cannot meaningfully
#' exist without (`q_id`, `entity`, `type_1`, `type_clean`, `region`) plus
#' `q_status`/`type_1` falling outside their controlled vocabularies.
#' Given 0% missingness on all five of those fields within ERCOT
#' (confirmed 2026-08-20), 0 rows are expected to fail today — this
#' machinery exists for a future malformed refresh, not because today's
#' data needs it. Genuinely "questionable but not invalid" conditions
#' (negative `mw_1`, missing `wd_date` on a withdrawn row, missing
#' `state`, etc.) are deliberately NOT exclusion criteria here — per
#' Samantha's explicit instruction those get kept and flagged instead, in
#' `flag_berkeley_lab_quality_issues()`.
#'
#' @param prepared_tbl `ercot` element of `prepare_berkeley_lab_ercot()`.
#' @return list(clean = tibble, excluded = tibble with `exclusion_reason`,
#'   checked = the full pre-filter tibble with its flag columns intact —
#'   passed on to `build_queued_up_quality_report()` so its counts read
#'   from the same flags rather than a second, separately-maintained copy).
validate_berkeley_lab_queue <- function(prepared_tbl) {
  checked <- prepared_tbl %>%
    dplyr::mutate(
      .missing_q_id        = is.na(q_id),
      .missing_entity      = is.na(entity),
      .missing_type_1      = is.na(type_1),
      .missing_type_clean  = is.na(type_clean),
      .missing_region      = is.na(region),
      .unexpected_q_status = !is.na(q_status) & !q_status %in% QUEUE_STATUS_LEVELS,
      .unexpected_type_1   = !is.na(type_1) & !type_1 %in% TYPE_1_LEVELS,
      .exclude = .missing_q_id | .missing_entity | .missing_type_1 |
        .missing_type_clean | .missing_region | .unexpected_q_status | .unexpected_type_1,
      exclusion_reason = dplyr::case_when(
        .missing_q_id        ~ "missing q_id",
        .missing_entity      ~ "missing entity",
        .missing_type_1      ~ "missing type_1",
        .missing_type_clean  ~ "missing type_clean",
        .missing_region      ~ "missing region",
        .unexpected_q_status ~ paste0("unexpected q_status: '", q_status, "'"),
        .unexpected_type_1   ~ paste0("unexpected type_1: '", type_1, "'"),
        TRUE ~ NA_character_
      )
    )

  excluded <- dplyr::filter(checked, .exclude)
  clean <- dplyr::filter(checked, !.exclude)

  list(clean = clean, excluded = excluded, checked = checked)
}

#' Add non-exclusionary quality flags to the validated clean tibble.
#' Nothing here removes a row — this is the concrete implementation of
#' "do not delete questionable records without documenting why": every
#' questionable condition becomes a boolean column in the shipped CSV
#' instead of a deletion. Also adds `q_status` as convenience `is_*`
#' booleans, satisfying "preserve source status information so I can
#' define the analytical subset later" — `q_status` itself is untouched,
#' and nothing here filters on it.
#'
#' @param clean_tbl `clean` element of `validate_berkeley_lab_queue()`.
#' @return `clean_tbl` with the flag columns added, in the final column
#'   order written to `data/processed/queued_up_clean.csv`.
flag_berkeley_lab_quality_issues <- function(clean_tbl) {
  clean_tbl %>%
    dplyr::mutate(
      # %in% rather than == deliberately: it's NA-safe (returns FALSE, not
      # NA, when q_status is NA), so a missing q_status can't cascade into
      # NA further down through flag_withdrawn_missing_wd_date's `&` and
      # corrupt the quality report's sum()s with a silent NA total.
      is_active         = q_status %in% "active",
      is_withdrawn      = q_status %in% "withdrawn",
      is_operational    = q_status %in% "operational",
      is_suspended      = q_status %in% "suspended",
      is_unknown_status = q_status %in% "unknown",
      flag_nonpositive_mw_1 = !is.na(mw_1) & mw_1 <= 0,
      flag_withdrawn_missing_wd_date   = is_withdrawn & is.na(wd_date),
      flag_operational_missing_on_date = is_operational & is.na(on_date),
      flag_missing_state = is.na(state),
      flag_missing_fips  = is.na(fips_code),
      # Codebook documents a literal 'not assigned' q_id value file-wide;
      # audited here rather than assumed absent from the ERCOT subset.
      flag_placeholder_q_id = !is.na(q_id) & tolower(q_id) == "not assigned",
      # Direct, ERCOT-scoped check on the region/state divergence
      # docs/decisions.md already warns about, in the reverse direction
      # (region=='ERCOT' rows whose state isn't 'TX', if any occur).
      flag_state_not_tx = !is.na(state) & state != "TX"
    ) %>%
    dplyr::add_count(q_id, entity, name = ".n_id_entity") %>%
    dplyr::mutate(flag_duplicate_q_id_entity = .n_id_entity > 1) %>%
    dplyr::select(
      q_id, entity, q_status,
      is_active, is_withdrawn, is_operational, is_suspended, is_unknown_status,
      q_date, q_year, prop_date, prop_year, on_date, wd_date, ia_date,
      ia_phase_raw, ia_phase_clean,
      county, state, fips_code, poi_name, region,
      project_name, utility, developer, cluster, service, project_type,
      type_1, type_2, type_3, type_clean,
      mw_1, mw_2, mw_3,
      flag_nonpositive_mw_1, flag_withdrawn_missing_wd_date,
      flag_operational_missing_on_date, flag_missing_state, flag_missing_fips,
      flag_duplicate_q_id_entity, flag_placeholder_q_id, flag_state_not_tx
    )
}

#' Build a long-format data-quality report for the Berkeley Lab ERCOT
#' cleaning pass, matching `build_ercotqueue_quality_report()`'s
#' section/field/metric/value shape for consistency across both sources.
#' Every count is read from flag columns `validate_berkeley_lab_queue()`
#' or `flag_berkeley_lab_quality_issues()` already computed — never
#' recomputed here, applying the lesson from the ERCOTQueue pipeline's
#' code review (recomputing the same predicate twice risks the two
#' silently drifting apart).
#'
#' @param checked_tbl `checked` element of `validate_berkeley_lab_queue()`.
#' @param clean_tbl Output of `flag_berkeley_lab_quality_issues()`.
#' @param excluded_tbl `excluded` element of `validate_berkeley_lab_queue()`.
#' @param n_total Total rows in the raw file, all regions.
#' @param n_ercot Rows with region == 'ERCOT'.
#' @param n_region_missing Rows with no `region` value at all — tracked
#'   separately from confirmed non-ERCOT rows, since
#'   `prepare_berkeley_lab_ercot()` excludes both from the ERCOT subset
#'   but they are not the same kind of row (one is a documented data gap,
#'   the other is a genuine other-region project).
#' @return A tibble with columns: section, field, metric, value.
build_queued_up_quality_report <- function(checked_tbl, clean_tbl, excluded_tbl,
                                            n_total, n_ercot, n_region_missing) {
  scope_filter <- tibble::tibble(
    section = "scope_filter", field = NA_character_,
    metric = c("rows_total_file", "rows_region_ercot", "rows_outside_ercot", "rows_region_missing"),
    value = as.character(c(n_total, n_ercot, n_total - n_ercot - n_region_missing, n_region_missing))
  )

  row_counts <- tibble::tibble(
    section = "row_counts", field = NA_character_,
    metric = c("rows_before_cleaning", "rows_after_cleaning", "rows_excluded"),
    value = as.character(c(nrow(checked_tbl), nrow(clean_tbl), nrow(excluded_tbl)))
  )

  status_counts <- clean_tbl %>%
    dplyr::count(q_status, name = "n") %>%
    dplyr::transmute(
      section = "status_counts", field = q_status,
      metric = "count", value = as.character(n)
    )

  missing_values <- purrr::imap_dfr(clean_tbl, function(col, name) {
    tibble::tibble(
      section = "missing_values", field = name,
      metric = "n_missing", value = as.character(sum(is.na(col)))
    )
  })

  # Fields at 100% missing within the ERCOT subset specifically (even if
  # partially populated file-wide, per docs/data_dictionary.md) — flagged
  # as structural, not a defect in this cleaning pass.
  structural_missingness <- missing_values %>%
    dplyr::filter(as.integer(value) == nrow(clean_tbl)) %>%
    dplyr::mutate(
      section = "structural_missingness",
      metric = "fully_missing_in_ercot_not_a_defect"
    )

  unexpected_categorical <- tibble::tibble(
    section = "unexpected_categorical", field = c("q_status", "type_1"),
    metric = "n_unexpected",
    value = as.character(c(
      sum(checked_tbl$.unexpected_q_status),
      sum(checked_tbl$.unexpected_type_1)
    ))
  )

  quality_flags_retained <- tibble::tibble(
    section = "quality_flags_retained",
    field = c(
      "nonpositive_mw_1", "withdrawn_missing_wd_date", "operational_missing_on_date",
      "missing_state", "missing_fips", "duplicate_q_id_entity",
      "placeholder_q_id", "state_not_tx"
    ),
    metric = "n_flagged_rows_kept",
    # na.rm = TRUE as a second line of defense — the flag columns
    # themselves are already NA-guarded (%in%/is.na patterns in
    # flag_berkeley_lab_quality_issues()), but a bare sum() over any
    # logical vector containing NA returns NA in R, which would otherwise
    # silently turn a real count into a missing value in the written CSV.
    value = as.character(c(
      sum(clean_tbl$flag_nonpositive_mw_1, na.rm = TRUE),
      sum(clean_tbl$flag_withdrawn_missing_wd_date, na.rm = TRUE),
      sum(clean_tbl$flag_operational_missing_on_date, na.rm = TRUE),
      sum(clean_tbl$flag_missing_state, na.rm = TRUE),
      sum(clean_tbl$flag_missing_fips, na.rm = TRUE),
      sum(clean_tbl$flag_duplicate_q_id_entity, na.rm = TRUE),
      sum(clean_tbl$flag_placeholder_q_id, na.rm = TRUE),
      sum(clean_tbl$flag_state_not_tx, na.rm = TRUE)
    ))
  )

  excluded_reasons <- if (nrow(excluded_tbl) == 0) {
    tibble::tibble(
      section = "excluded_records", field = NA_character_,
      metric = "count", value = "0"
    )
  } else {
    excluded_tbl %>%
      dplyr::transmute(
        section = "excluded_records", field = q_id,
        metric = "exclusion_reason", value = exclusion_reason
      )
  }

  guardrail_notes <- tibble::tibble(
    section = "notes", field = NA_character_, metric = "caveat",
    value = c(
      paste(
        "Interconnection queue MW (mw_1/mw_2/mw_3) is potential future",
        "generation capacity in the queue, not deliverable MW."
      ),
      paste(
        "q_status is preserved unfiltered — is_active/is_withdrawn/",
        "is_operational/is_suspended/is_unknown_status are convenience",
        "flags, not a pre-applied analytical subset."
      ),
      "Geographic filter is region=='ERCOT', not state=='TX' — see docs/decisions.md, 2026-08-17."
    )
  )

  dplyr::bind_rows(
    scope_filter, row_counts, status_counts, missing_values,
    structural_missingness, unexpected_categorical, quality_flags_retained,
    excluded_reasons, guardrail_notes
  )
}

#' Clean the Berkeley Lab "Queued Up" ERCOT subset end to end: read,
#' filter/prepare, validate, flag, and write both the cleaned dataset and
#' its data-quality report to disk.
#'
#' @param path Path to the raw workbook.
#' @param sheet Sheet name within the workbook.
#' @return list(clean, excluded, quality_report) — also written to
#'   `data/processed/queued_up_clean.csv` and
#'   `output/analysis/queued_up_quality_report.csv`.
clean_queued_up_data <- function(path = BERKELEY_LAB_XLSX, sheet = BERKELEY_LAB_SHEET) {
  raw_tbl   <- read_berkeley_lab_raw(path, sheet)
  scoped    <- prepare_berkeley_lab_ercot(raw_tbl)
  validated <- validate_berkeley_lab_queue(scoped$ercot)
  clean     <- flag_berkeley_lab_quality_issues(validated$clean)
  quality_report <- build_queued_up_quality_report(
    validated$checked, clean, validated$excluded,
    scoped$n_total, scoped$n_ercot, scoped$n_region_missing
  )

  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  dir.create("output/analysis", recursive = TRUE, showWarnings = FALSE)

  readr::write_csv(clean, "data/processed/queued_up_clean.csv")
  readr::write_csv(quality_report, "output/analysis/queued_up_quality_report.csv")

  list(clean = clean, excluded = validated$excluded, quality_report = quality_report)
}

result <- import_ercot_large_load()
print(result$queue_summary)

cleaned <- clean_ercot_large_load_projects(result$raw_paths[["load_projects"]])
print(cleaned$quality_report)

queued_up <- clean_queued_up_data()
print(queued_up$quality_report)
