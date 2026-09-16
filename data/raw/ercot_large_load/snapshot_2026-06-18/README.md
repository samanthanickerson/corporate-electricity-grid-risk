# ERCOT Large Load queue — snapshot of 2026-06-18

The demand-side source data for every published figure in this project.

## What this is

Two JSON responses from ercotqueue.com's public API, captured on
**2026-08-19** and carrying an `as_of_date` of **2026-06-18**:

| File | Size | Contents |
|---|---|---|
| `load_queue_summary.json` | 4.4 KB | Aggregate queue totals by status and sector — the source of the 420,812 MW `data_center` demand figure |
| `load_projects.json` | 8.1 KB | Project-level records published by the source |

## Why it is committed

`data/raw/` is otherwise gitignored, for size and licensing reasons. These
two files are the deliberate exception, for two reasons:

1. **They are the anchor for every number in this project.** The
   `as_of_date` of 2026-06-18 determines the demand figure, and through it
   the Demand Pressure Ratio, the Delivery Gap, and the composite
   Procurement Risk Score. Without them the published results cannot be
   reproduced or checked by anyone — including a future version of this
   project.
2. **Redistribution is permitted.** See the license note below.

At 12.5 KB combined there is no size argument against committing them.

## How `R/01` uses this

`R/01_import_clean.R` reads `data/raw/ercot_large_load/` one level up,
which is gitignored. On a fresh clone that directory is empty, so `R/01`
**copies these two files into place automatically** and does not contact
the live endpoint. No manual step is needed.

The working copy stays refreshable. To pull a newer snapshot deliberately:

```bash
ERCOT_LARGE_LOAD_REFRESH=TRUE Rscript R/01_import_clean.R
```

That warns before replacing the working file and leaves this committed
copy untouched, so the 2026-06-18 anchor is never lost.

## Attribution (required)

Data from **ERCOTQueue.com**, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), citing the
ERCOT Large Load Working Group (LLWG) "Large Load Interconnection Status
Update" reports.

CC BY 4.0 explicitly permits redistribution with attribution, which is why
these files can be committed while the Berkeley Lab workbook cannot.

## Provenance caveat

ercotqueue.com is a **third-party republication** of ERCOT's Large Load
Working Group filings. Its figures cite specific source reports and slide
numbers, but this project has **not** independently cross-checked them
against ERCOT's original documents — a standing `[NEEDS VERIFICATION]`
flag in `docs/data_dictionary.md`, and an open item under "Future work" in
`README.md`.
