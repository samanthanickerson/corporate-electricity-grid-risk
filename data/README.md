# data/

## `raw/`

One subfolder per source, matching the data-sources list in the top-level
`CLAUDE.md`:

- `ercot_large_load/` — ERCOT Large Load interconnection queue, the core
  demand-side dataset (see `docs/decisions.md`, 2026-08-17). Fetched from
  ercotqueue.com's public JSON API (`load_queue_summary.json`,
  `load_projects.json`) as of 2026-08-19.
- `berkeley_lab/` — Berkeley Lab "Queued Up" interconnection queue data,
  filtered to `region == 'ERCOT'` (not `state == 'TX'` — see
  `docs/decisions.md`). Acquisition instructions below.
- `ercot_gis/` — **empty; this source was never fetched.** The ERCOT
  Generator Interconnection Status download endpoints are disallowed by
  `robots.txt`, and routing around that was rejected (`docs/decisions.md`,
  2026-08-15). `scripts/` contains no fetch script.
- `context/` — **empty.** EIA generation mix, NREL SLOPE technical
  potential, and DSIRE policy data were identified during reconnaissance
  as useful context but are not part of the current pipeline.

Files placed here should be exactly as downloaded — no edits, no renaming
beyond adding a fetch date if useful. `raw/` is listed in `.gitignore` and
is **not committed**: source files are large, some are licensed for
non-redistribution, and all are re-fetchable from the original sources
above.

### Obtaining the raw data

`raw/` is empty in a fresh clone. Both sources must be fetched before
`R/01_import_clean.R` will run. Neither is redistributed here.

**1. Berkeley Lab "Queued Up" (supply side) — manual download**

| | |
|---|---|
| Source | Lawrence Berkeley National Laboratory, *Queued Up* |
| URL | <https://emp.lbl.gov/queues> |
| File to download | the interconnection-queue data workbook (`.xlsx`) |
| Save as | `data/raw/berkeley_lab/Queued_Up_Data.xlsx` |
| Sheet used | `03. Complete Queue Data` (the workbook has 41 sheets; the other 40 are LBNL's own pre-aggregated summaries and are not read) |
| Edition used in this analysis | the edition covering **interconnection requests submitted through the end of 2025**, per the workbook's own `00. Background + Methods` sheet |
| Downloaded | **2026-08-15** |
| Size / shape as downloaded | 14.85 MB; **38,201 data rows × 30 columns** on the sheet used |

**Version-check before you trust a re-run.** LBNL republishes *Queued Up*
annually, and a later edition will contain more rows and shift every
supply-side figure in this project. After downloading, confirm the sheet
has 38,201 rows and that `00. Background + Methods` says requests through
end of 2025. If it doesn't, you have a different edition — the pipeline
will still run, but the numbers in `README.md`, `docs/`, and
`output/analysis/` describe the 2026-08-15 edition and will no longer
match.

**Why it isn't committed:** at ~15 MB it is a third party's research
dataset. Redistribution terms are LBNL's to set, and committing the file
would answer that question implicitly. The download is free and requires
no account.

**2. ERCOT Large Load queue (demand side) — fetched by script**

`R/01_import_clean.R` pulls `load_queue_summary.json` and
`load_projects.json` from ercotqueue.com's public JSON API. This is
licensed **CC BY 4.0**, so redistribution with attribution is permitted.

**This source is a live endpoint with no version pinning**, and it
advances as ERCOT publishes new Large Load Working Group reports. A re-run
today will not reproduce the `as_of_date` of **2026-06-18** used
throughout this analysis. To reproduce the published figures exactly, a
date-stamped snapshot of both JSON responses would need to be committed;
see `docs/reproducibility_audit.md`.

## `processed/`

Cleaned/joined outputs produced by the numbered `R/` pipeline scripts.
Also gitignored — regenerate by re-running the pipeline rather than hand-
editing anything here. Per the hard guardrail in `CLAUDE.md`, each pipeline
stage writes a **new** file rather than overwriting the previous stage's
output.

## `procurement.db` — not built

`CLAUDE.md` describes a SQLite database built and queried from R via
`DBI`/`RSQLite`. **It was never created.** No script in `R/` opens a
database connection; the pipeline is `dplyr` from ingestion through
scoring. It is listed as future work in `README.md`. Nothing in this
project reads or writes `data/procurement.db`.
