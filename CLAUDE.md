# CLAUDE.md

This file is read automatically by Claude Code at the start of every session
in this repository. It exists so project conventions don't need to be
re-explained each time.

## Project

**Corporate Electricity Demand vs. Grid Interconnection Capacity (ERCOT Focus)**

Research question: *Where is corporate electricity demand outpacing the
grid's interconnection capacity to deliver it, and by how much?*

**Naming note (2026-08-26):** this project was originally scoped as
"Corporate Clean Energy Demand" before any pipeline code existed. Once
built, the pipeline never filtered either side of the comparison by
generation technology — see `docs/analytical_critique.md` §0 and
`docs/decisions.md` (2026-08-26) — so the name and research question
were corrected to describe what is actually measured: corporate
electricity demand (not clean-energy-specific demand) against grid
interconnection capacity (not generation technology mix).

Primary region: **ERCOT (Texas)** — chosen as a single-state grid with the
most acute, well-documented tension between corporate procurement demand
and interconnection queue capacity of any U.S. grid region.

## Data sources

**Core:**
1. ERCOT Large Load interconnection queue — demand-side dataset: large
   (often corporate/data-center/industrial) loads seeking to interconnect
   in Texas. Texas-native by construction. Fetched via ercotqueue.com's
   public JSON API as of 2026-08-19 (see `docs/decisions.md`,
   2026-08-17/2026-08-19); the `data_center` sector figure is the
   demand-side unit in use, per the 2026-08-19 decision.
2. Berkeley Lab "Queued Up" — national generation interconnection queue
   data, filtered to `region == 'ERCOT'` (**not** `state == 'TX'` — these
   are not interchangeable; see `docs/decisions.md`, 2026-08-17)
3. ERCOT Generator Interconnection Status (GIS) report — Texas-specific, more current supplement, fetched monthly

**Secondary/context (enrich, don't replace, the core analysis):**
4. EIA — Texas generation mix and capacity data
5. NREL SLOPE — Texas renewable technical potential
6. DSIRE — Texas clean energy policy/incentive context

## Your role vs. mine (Claude Code)

**I am the analyst, researcher, and project owner.** I am responsible for:
- Defining the research question and methodology
- Deciding what constitutes "demand" and "grid delivery capacity"
- Choosing the geographic/temporal unit
- Reviewing your proposed methodology before it's implemented
- Validating calculations, interpreting results, writing final conclusions

**You are my coding agent and technical assistant.** Use you for:
- Inspecting and cleaning data, writing R scripts, debugging, refactoring
- Running SQL (via `DBI`/`RSQLite`, executed from R — see Tech stack below)
- Building visualizations, managing git, drafting documentation

**Do not** treat "analyze this and tell me the answer" as an instruction to
run the full pipeline unsupervised. Instead: inspect → explain what you
found → propose an approach → wait for my approval → implement → validate
→ document. Use **plan mode** by default for anything involving a
methodological judgment call (dataset reconnaissance, geography/time
alignment, risk-score design, methodology comparisons, analytical
critique) — toggle with `Shift+Tab`, or launch with
`claude --permission-mode plan`. Pure implementation steps I've already
approved (e.g., "write the cleaning script we just discussed") don't need
plan mode.

## Tech stack & conventions

- **R/RStudio** is the primary environment. One R Notebook or a numbered
  `R/` script sequence — both are fine, but keep the numbering (`01_`,
  `02_`, …) so execution order is unambiguous.
- **SQL runs inside R**, via `DBI` + `RSQLite` against `data/procurement.db`.
  Write real SQL query strings executed with `dbGetQuery()`/`dbExecute()` —
  don't silently substitute `dplyr` joins for what should be a SQL exercise,
  since demonstrating SQL is part of the point of this project. Note in a
  comment if you do choose `dplyr` for something SQLite handles awkwardly
  (e.g., `FULL OUTER JOIN`), and explain why.
  **Status: not built.** No script in `R/` opens a database connection and
  `data/procurement.db` does not exist; the pipeline is `dplyr` end to end.
  This bullet is standing intent, not a description of the repository — see
  "Future work" in `README.md`.
- **tidyverse style** for anything not done in raw SQL — `dplyr`, `ggplot2`.
- **Tableau** is the final dashboard layer, built from an exported CSV. Don't
  try to replicate dashboard logic in R beyond exploratory plots.
- Use the **Playwright skill** for the ERCOT GIS fetch (`scripts/fetch_ercot_gis.R`
  or equivalent) — the download URL changes monthly, so locate the current
  link rather than hardcoding one. Check `robots.txt` first and report what
  you find before downloading anything.
  **Status: not built, and deliberately so.** The GIS download endpoints are
  disallowed by `robots.txt` and routing around that was rejected
  (`docs/decisions.md`, 2026-08-15). `scripts/` is empty.
- Run the **`/code-review` skill** on any new or modified `R/` pipeline
  script before treating it as validated or committing it — catches
  correctness bugs before the code is trusted. Not needed for
  documentation-only changes.
- Run the **`/qa` skill** (project-scoped, `.claude/skills/qa/`) after a
  pipeline script has actually produced output — checks the resulting
  `data/processed/*.csv` and `output/analysis/*_quality_report.csv`
  against invariants already documented in `docs/data_dictionary.md` and
  `docs/decisions.md`. Complementary to `/code-review`: that checks the
  code, this checks what the code produced.
  **Status: the skill was never written**, and `.claude/skills/qa/` does not
  exist in this repository. These checks were carried out by hand instead.
  Either write the skill or drop this bullet — as written it instructs a
  reader to run something that isn't here.

## Hard guardrails — do not violate these

- **Interconnection queue MW is not deliverable MW.** Never phrase a finding
  as "the queue equals future generation." Use language like "potential
  future generation capacity in the interconnection queue."
- **Never silently drop records.** Any exclusion during cleaning needs a
  documented reason (row count before/after, why excluded).
- **Never claim causality** the data can't support. Report what's directly
  observed; flag correlation vs. causation risk explicitly.
- **The Procurement Risk Score is an analytical construct, not objective
  truth.** Always present it with its weighting scheme and sensitivity
  results alongside it, never as a bare ranking.
- **Don't overwrite earlier processed datasets** — each pipeline stage
  should write a new file, not mutate the previous stage's output in place.

## Repository structure

```
corporate-electricity-grid-risk/
├── README.md
├── CLAUDE.md
├── LICENSE
├── .gitignore
├── R/                    # 01, 03–10: numbered pipeline scripts
├── data/
│   ├── README.md
│   ├── raw/              # gitignored; re-fetchable from the documented sources
│   └── processed/        # gitignored except tableau_final.csv
├── output/
│   ├── analysis/         # findings tables, quality reports, sensitivity results
│   └── figures/          # 11 committed ggplot2 charts
├── tableau/              # data guide, dashboard design, build steps
├── docs/                 # decisions, metric definitions, critique, reviews
├── notebooks/            # empty (.gitkeep) — no notebook was written
└── scripts/              # empty (.gitkeep) — the GIS fetch was never built
```

This diagram describes the repository as it actually is. `data/procurement.db`
and `scripts/fetch_ercot_gis.R` appear in the conventions above as standing
intent; neither exists.

## Documentation expectations

Every methodological decision gets recorded in `docs/decisions.md` before
implementation proceeds. Every cleaning pass produces a data-quality report
(row counts, exclusions, missing values). `docs/AI_WORKFLOW.md` should stay
current with an honest account of what you did vs. what I decided — this
project's portfolio value depends on that distinction being real, not
performative.

## Git commits

Small, meaningful commits over one large one — e.g. `Add source data
documentation`, `Add ERCOT Large Load import workflow`, `Integrate
procurement and queue datasets`, `Add risk score sensitivity analysis`.
This should read as a real development history, not a single
AI-generated dump.
