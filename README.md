# Corporate Electricity Demand vs. Grid Interconnection Capacity (ERCOT Focus)

An end-to-end R analytics project comparing large-load electricity demand
against generation interconnection capacity in the ERCOT (Texas) grid
region, with a composite risk indicator, a sensitivity analysis, and a
Tableau dashboard specification.

> **Naming note:** this project was originally scoped as "Corporate *Clean
> Energy* Demand." Once the pipeline was built, a self-review confirmed it
> never filters either side of the comparison by generation technology, so
> the title and research question were corrected to describe what is
> actually measured (`docs/analytical_critique.md` §0, `docs/decisions.md`
> 2026-08-26).

## Research question

**Where is corporate electricity demand outpacing the grid's
interconnection capacity to deliver it, and by how much?**

## Project overview

Large electricity users and new power plants both join the grid through
**interconnection queues** — formal waiting lists run by the grid
operator. This project builds a reproducible pipeline that pulls two
public interconnection-queue datasets for ERCOT, aligns them on a common
geography and point in time, and quantifies the relationship between them.

The pipeline produces four analytical metrics, a composite **Procurement
Risk Score**, a sensitivity analysis testing how much that score depends
on methodological choices, eleven figures, and a Tableau-ready dataset
with a full dashboard specification.

**Scope, stated up front:** the analysis covers **one region (ERCOT) at
one point in time** (snapshot date 2026-06-18). It supports no trend
analysis and no cross-region comparison — the demand-side source publishes
a single cross-section with no project-level history. Everything below is
framed accordingly.

## Why this question matters

Data centers and other large industrial facilities need very large amounts
of electricity, and they must apply to connect to the grid. New generation
must apply through a parallel process. Whether enough generation capacity
is moving through the queue to serve the load requesting connection is a
practical question for corporate energy procurement, utility planning, and
siting decisions.

It is also a genuinely hard question to measure well, which is the
analytical point of this project. A megawatt in an interconnection queue
is a **request**, not delivered power. Many queued projects are never
built. Any honest answer therefore has to quantify not just the headline
supply-versus-demand balance, but how much of that queued capacity has
historically failed to materialize — and has to be explicit about where
the measurement stops and interpretation begins.

## Data sources

### Integrated in this analysis

| Source | Role | Notes |
|---|---|---|
| **ERCOT Large Load interconnection queue**, via [ercotqueue.com](https://www.ercotqueue.com)'s public JSON API | Demand side — large loads (data centers, industrial) seeking to connect in Texas | Licensed CC BY 4.0. Aggregate buckets only; no project-level rows are published. The `data_center` sector figure is the demand unit used. |
| **Berkeley Lab, [*Queued Up*](https://emp.lbl.gov/queues)** | Supply side — generation projects seeking interconnection nationally, filtered to ERCOT | 3,757 ERCOT rows; 3,608 in scope after the snapshot-date cutoff. |

**Provenance caveat carried throughout:** ercotqueue.com is a third-party
republication of ERCOT's Large Load Working Group filings. Its figures cite
specific source reports and slide numbers, but this project has **not**
independently cross-checked them against ERCOT's original documents — a
standing `[NEEDS VERIFICATION]` flag in `docs/data_dictionary.md`.

### Identified but not integrated

The ERCOT Generator Interconnection Status report was not fetched: its
download endpoints are disallowed by `robots.txt`, and routing around that
was rejected (`docs/decisions.md`, 2026-08-15). EIA generation-mix, NREL
SLOPE, and DSIRE policy data were identified as useful context but are not
part of the current pipeline. These remain future work rather than
contributors to any number reported here.

## Methodology

Nine numbered R scripts, each reading only files persisted by earlier
stages and writing a new file rather than mutating an existing one:

| Script | Purpose |
|---|---|
| `R/01_import_clean.R` | Fetch and clean both sources; emit data-quality reports |
| `R/03_data_integration.R` | Align on geography and snapshot date; emit a reconciliation report |
| `R/04_metrics.R` | Compute the four analytical metrics |
| `R/05_risk_score.R` | Normalize components and compute the composite score |
| `R/06_sensitivity_analysis.R` | Re-score under three alternative weighting schemes |
| `R/07_visualizations.R` | Generate 11 figures |
| `R/08_manual_validation_sample.R` | Hand-checkable worked examples through the real formulas |
| `R/09_tableau_export.R` | Build the Tableau-ready dataset |
| `R/10_top_risk_regions.R` | Emit the factual findings table |

Two structural decisions a reader should know:

- **ERCOT is matched on `region == 'ERCOT'`, not `state == 'TX'`.** These
  are not interchangeable — 539 Berkeley Lab rows sit in Texas but on other
  grids (Panhandle, El Paso area). Using the state filter would pull in
  non-ERCOT projects (`docs/decisions.md`, 2026-08-17).
- **The two datasets are parallel aggregates, not a row-level join.** The
  demand source publishes only pre-aggregated buckets, so there is no key
  to join on. Each side is aggregated independently and compared; no
  project-to-project matching is claimed.

Every methodological decision, including ones later reversed, is recorded
with rationale and alternatives in `docs/decisions.md`. Formula definitions
and hand-verified validation examples are in `docs/metric_definitions.md`.

## The Procurement Risk Score

**The Procurement Risk Score is an analytical construct, not an objective
measurement.** It is a weighted average of four normalized indicators,
built from methodological choices this project made explicitly and
documents openly. It is presented here only alongside its weighting scheme
and its sensitivity results.

### Components and weights

The weights represent three conceptual slots of equal importance —
demand-vs-supply, queue attrition, and queue age — with the first slot
split evenly between its two mathematically redundant expressions (Demand
Pressure Ratio and Delivery Gap MW use the same two inputs, one as a ratio
and one as a difference), so that relationship is not double-counted.

| Component | What it captures | Weight |
|---|---|---:|
| Queue Attrition | Share of all queued capacity ever withdrawn | 1/3 (0.333) |
| Queue Age | How long active projects have been waiting | 1/3 (0.333) |
| Demand Pressure | Demand ÷ total queue capacity | 1/6 (0.167) |
| Delivery Gap | Demand − total queue capacity | 1/6 (0.167) |

### How the score is calculated

Each component is normalized to a 0–100 scale, then weighted. For this
snapshot the normalized components are 32.00 (Queue Attrition), 24.58
(Queue Age), 10.63 (Demand Pressure), and 2.39 (Delivery Gap):

```
(1/3 × 32.00) + (1/3 × 24.58) + (1/6 × 10.63) + (1/6 × 2.39)
=    10.67     +     8.19      +     1.77      +     0.40
= 21.03
```

This uses the component values as computed, not as rounded for display;
substituting whole-number approximations (32, 25, 11, 2.4) yields ≈21.2
instead. If a component were ever missing, it would be excluded and the
remaining weights rescaled to sum to 1, with the exclusion recorded in the
output. No component was excluded here.

### Why it is an indicator, not a measure

- The weighting is defensible but **subjective** — a different analyst
  could reasonably choose differently and get a different number, as the
  sensitivity analysis below demonstrates directly.
- Three of the four normalization thresholds are **provisional
  placeholders**, not calibrated against domain benchmarks or accumulated
  history (`docs/risk_score_design.md`). Only Queue Attrition is a true
  bounded proportion.
- The score has **no calibrated bands**. Describing a value as "low" or
  "moderate" is a reading of a 0–100 number, not a classification the
  methodology defines.
- It has **never been back-tested** against a real procurement or
  interconnection outcome, so it carries no demonstrated predictive
  validity.

## Key findings

*ERCOT, snapshot date 2026-06-18. Figures quoted from
`output/analysis/top_risk_regions.csv` and
`output/analysis/risk_score_sensitivity.csv`.*

### Answering the research question

**At this snapshot, in ERCOT, corporate demand is not outpacing
interconnection capacity.** Large-load (data-center sector) demand of
**420,812 MW** sits below the **791,939 MW** of generation capacity that
has cumulatively entered the ERCOT queue since 1995 — a Delivery Gap of
**−371,127 MW** and a Demand Pressure Ratio of **0.53**. The gap is
negative: cumulative queued capacity exceeds current demand rather than
falling short of it.

This answers *how much*, for one region at one point in time. It does not
answer *where* comparatively — the dataset contains a single region.

### Observed values

| Metric | Value |
|---|---|
| Corporate Demand | 420,812 MW |
| Active Queue Capacity | 407,412 MW |
| Total Queue Capacity (all statuses, cumulative) | 791,939 MW |
| Demand Pressure Ratio (demand ÷ total queue) | 0.53 |
| Delivery Gap (demand − total queue) | −371,127 MW |
| Queue Attrition Rate | 0.32 |
| Queue Age (MW-weighted median, active projects) | 897 days |
| Procurement Risk Score (base-case weighting) | 21.0 |

The Queue Attrition Rate of 0.32 means **32% of all generation capacity
(in MW) that has ever entered the ERCOT queue since 1995, through the
2026-06-18 snapshot, has since been withdrawn.** This is a cumulative,
pooled figure across all queue vintages — not a cohort or time-to-event
rate.

![Bar chart of the four normalized risk-score components for the ERCOT
snapshot of June 18, 2026: Queue Attrition 32, Queue Age 25, Demand
Pressure 11, Delivery Gap 2, on a 0–100 scale.](output/figures/risk_score_component_comparison.png)

*The two queue-side components carry both the highest normalized values and
two-thirds of the base-case weight. Normalization thresholds for Queue Age,
Demand Pressure, and Delivery Gap are provisional and not empirically
calibrated — there is only one observation, so no distribution exists to
calibrate against (`docs/risk_score_design.md`).*

### Sensitivity to the weighting scheme

| Scenario | Queue-side weight (attrition + age) | Score | vs. base | Largest weighted-contribution shift |
|---|---:|---:|---:|---|
| Demand-pressure-heavy | 40% | 15.2 | −5.8 | Queue Attrition |
| **Base case** | **67%** | **21.0** | — | — |
| Queue-risk-heavy | 80% | 23.9 | +2.9 | Queue Attrition |

![Procurement Risk Score under three weighting scenarios: base case 21.0,
demand-pressure-heavy 15.2, queue-risk-heavy 23.9, on a 0–100
scale.](output/figures/risk_score_sensitivity.png)

*The same underlying data produces a roughly 9-point spread across three
defensible weightings. The figures are in
`output/analysis/risk_score_sensitivity.csv`; the reasoning is in
`docs/risk_score_sensitivity_interpretation.md`.*

### Interpretation

*Analyst interpretation of the observed values above — not additional
measurement.*

The score of 21.0 reads as low overall risk on the supply-versus-demand
question, consistent with cumulative queued capacity substantially
exceeding current demand: an abundance of *potential* capacity in the
queue.

That reading is not robust to the weighting scheme. Queue Attrition and
Queue Age together carry two-thirds of the base-case weight, and both read
as moderate rather than low (32.0 and 24.6 on a 0–100 scale). Across three
defensible weightings the score moves roughly 9 points — 15.2 to 23.9 —
and in both alternatives Queue Attrition is the component whose weighted
contribution shifts most. The headline reading therefore depends
materially on a methodological choice, not on the data alone.

The attrition figure is the substantive counterweight to the
abundant-capacity reading: roughly a third of all capacity that has ever
sought interconnection in ERCOT has ultimately been withdrawn.

## Tableau dashboard

The dashboard layer is built from `data/processed/tableau_final.csv` — a
single-row export carrying every metric, normalized component, weight, and
sensitivity result needed for presentation.

Three linked dashboards, specified to answer the research question in
roughly two minutes of exploration:

1. **Executive Overview** — the headline demand-vs-capacity comparison and
   the risk score with a condensed sensitivity strip.
2. **Regional Risk** — the ERCOT map and regional indicators, with the
   single-region scope stated before the map itself.
3. **Drivers of Risk** — the component breakdown with an interactive
   weighting-scenario selector, and the full sensitivity chart.

Specifications live in `tableau/`:
- `README.md` — field-by-field data dictionary for the export
- `dashboard_design.md` — chart types, KPIs, filters, tooltips, titles,
  subtitle language, and visual order per dashboard
- `build_steps.md` — click-by-click build instructions, calculated-field
  formulas, and a QA checklist

The workbook itself is built in Tableau Desktop from these specs; no
`.twbx` is committed.

## Tools

- **R** with the **tidyverse** (`dplyr`, `readr`, `purrr`, `tibble`) —
  data cleaning, integration, metrics, and scoring
- **ggplot2** — the 11 figures in `output/figures/`, committed to the
  repository so they are readable without running R
- **httr**, **jsonlite**, **readxl** — API and spreadsheet ingestion
- **Tableau Desktop** — dashboard layer, built from the exported CSV
- **Git** — version control, with a decision log kept alongside the code

## Repository structure

```
corporate-electricity-grid-risk/
├── README.md
├── CLAUDE.md                  # collaboration conventions for AI-assisted work
├── LICENSE                    # MIT
├── R/                         # 01, 03–10: numbered pipeline scripts
├── data/
│   ├── README.md              # how to obtain the raw sources
│   ├── raw/                   # not committed — fetch per data/README.md
│   └── processed/             # not committed, except tableau_final.csv
├── output/
│   ├── analysis/              # findings tables, quality reports, sensitivity results
│   └── figures/               # 11 committed ggplot2 charts
├── tableau/                   # dashboard data guide, design spec, build steps
├── docs/                      # decisions, metric definitions, critique, reviews
├── notebooks/                 # empty — no notebook was written
└── scripts/                   # empty — the ERCOT GIS fetch was never built
```

**`data/` is regenerated, not committed.** Raw sources are excluded for size
and licensing reasons and re-fetched per `data/README.md`; intermediate
processed CSVs are rebuilt by the pipeline. The one exception is
`data/processed/tableau_final.csv`, committed because it is the documented
handoff to the Tableau layer. Documentation elsewhere in this repository
therefore references `data/processed/` files that only exist after a run.

**Script numbering skips `02`.** `01` handles both sources' import and
cleaning; the slot reserved for a second import stage was never needed.

## Getting started

Tested on **R 4.6.1** (2026-06-24) on macOS. No `renv.lock` is committed
yet, so package versions are not pinned — see *Future work*.

**1. Install the packages**

```r
install.packages(c(
  "dplyr", "readr", "purrr", "tibble", "stringr",
  "ggplot2", "scales",
  "httr", "jsonlite", "readxl"
))
```

**2. Obtain the raw data**

The two sides differ, so read this before running anything.

**Demand side — nothing to do.** The ERCOT Large Load snapshot that every
published figure describes (`as_of_date` **2026-06-18**) is committed at
`data/raw/ercot_large_load/snapshot_2026-06-18/`, 12.5 KB, under its
CC BY 4.0 license. `R/01` copies it into place automatically on a fresh
clone and will **not** contact the live endpoint unless you ask it to.
That is deliberate: the endpoint advances, so downloading fresh would
silently recompute every figure on a different date. To pull a newer
snapshot on purpose:

```bash
ERCOT_LARGE_LOAD_REFRESH=TRUE Rscript R/01_import_clean.R
```

**Supply side — one manual download.** The Berkeley Lab "Queued Up"
workbook is 15 MB and is **not** redistributed here; its terms are LBNL's
to set. Follow the acquisition instructions in
[`data/README.md`](data/README.md), which record the URL, the sheet used,
the edition this analysis ran on, and a version check.

**3. Run the pipeline in order, from the repository root**

Every script uses paths relative to the repository root, so set your
working directory there first (in RStudio: open the project folder; from a
shell: `cd` into the clone).

```bash
Rscript R/01_import_clean.R            # fetch + clean both sources
Rscript R/03_data_integration.R        # align on geography and snapshot date
Rscript R/04_metrics.R                 # the four analytical metrics
Rscript R/05_risk_score.R              # normalize and composite the score
Rscript R/06_sensitivity_analysis.R    # re-score under 3 alternative weightings
Rscript R/07_visualizations.R          # the 11 figures
Rscript R/08_manual_validation_sample.R
Rscript R/09_tableau_export.R          # build data/processed/tableau_final.csv
Rscript R/10_top_risk_regions.R        # the findings table
```

The order matters: each stage reads files written by earlier stages and
writes a new file rather than mutating one. Scripts `07`–`10` can be run in
any order once `05` and `06` have completed.

**4. What will and will not reproduce**

The **demand side reproduces exactly**, from the committed snapshot.

The **supply side may not**. Berkeley Lab republishes *Queued Up*
annually, and a later edition contains more rows, which shifts the total
queue capacity, the attrition rate, and every figure derived from them.
`data/README.md` explains how to check which edition you have.
`docs/reproducibility_audit.md` covers this gap and scores the project
accordingly.

## Limitations

**Interconnection queue MW is a proxy for future grid-delivery capacity,
not a measure of it.** This is the project's central caveat:

- A queued megawatt is a **request to interconnect**, not a commitment
  that power will be delivered. Queued MW is never treated here as
  guaranteed generation.
- **The 32% attrition rate is direct evidence of that gap.** Nearly a
  third of all capacity ever entered has been withdrawn, so historical
  queue entry has demonstrably not translated into delivery at anything
  near a 1:1 rate.
- **The cumulative-vs-active choice changes the answer materially.**
  Demand Pressure and Delivery Gap are computed against total cumulative
  queue capacity (791,939 MW). Against *active* capacity alone
  (407,412 MW) the ratio would be near parity rather than 0.53
  (`docs/decisions.md`, 2026-08-26).
- **No locational deliverability.** Aggregate MW says nothing about
  whether that capacity can physically reach the nodes where large loads
  are sited.
- **The two sides are independently aggregated totals**, sharing only the
  unit "MW" — load-interconnection and generation-interconnection requests
  are structurally different quantities.
- **Source provenance** — the demand figure comes from a third-party
  republication not independently verified against ERCOT's originals.

**Scope limits:** one snapshot (no trend, no persistence claim), one region
(no ranking or cross-region comparison), and no causal analysis — nothing
in this design distinguishes correlation from causation, and none is
asserted.

A fuller skeptical review, including findings the project chose *not* to
act on, is in `docs/analytical_critique.md`.

## AI-assisted development

This project was built with Claude Code as a coding assistant, under an
explicit division of responsibility documented in `CLAUDE.md` and logged
throughout in `docs/AI_WORKFLOW.md`.

**Analyst (Samantha Nickerson):** defined the research question and
methodology, chose the geographic and temporal units, decided what counts
as demand and as capacity, approved every methodological change before
implementation, validated the calculations, and wrote the interpretation
of results.

**Claude Code:** implemented and debugged the R pipeline, ran code reviews
on every script before it was trusted, produced the visualizations and
Tableau specifications, and maintained the documentation.

`docs/AI_WORKFLOW.md` records this distinction honestly for each work
session — including scope conflicts raised before implementation, review
findings that required rework, and claims excluded from write-ups because
the data did not support them.

### A note on `docs/`

Three documents in `docs/` are **deliberate self-audits of this project**,
commissioned and published on purpose rather than left out:

| Document | What it is |
|---|---|
| `final_code_review.md` | A senior-level review of all nine R scripts, ranking issues CRITICAL / HIGH / MEDIUM / LOW with a fix for each |
| `reproducibility_audit.md` | An attempt to reproduce this project from a clean clone, scored 0–100 against ten criteria |
| `github_release_checklist.md` | A pre-publication scan for secrets, personal data, broken references, and naming inconsistencies |

They are critical of the work by design. Their findings drove real
changes — the conditional fetch in `R/01` and the committed source
snapshot both came directly from them, as did several corrections to these
documents' own errors, which are marked in place rather than quietly
edited out.

A reproducibility score of 54/100 is not a verdict on the analysis. It
measures a specific, named gap: the pipeline was not built to be re-run by
a stranger, and the audit says so with the evidence. Knowing where the
work is weak, and writing it down, is the point.

## Future work

Grounded in the "revisit if" conditions logged in `docs/decisions.md` and
the robustness checks recommended in `docs/analytical_critique.md`:

- **Accumulate repeated snapshots.** The single largest limitation. Running
  the pipeline on a schedule would enable genuine trend analysis, a real
  demand-side time series, and an empirical distribution to calibrate the
  normalization thresholds against.
- **Verify the demand source.** Cross-check ercotqueue.com's figures
  against ERCOT's original Large Load Working Group filings at least once,
  to resolve the standing `[NEEDS VERIFICATION]` flag.
- **Calibrate the normalization thresholds**, replacing the current
  provisional placeholders with empirically grounded reference ranges.
- **Pin the environment.** No `renv.lock` is committed, so package
  versions are unpinned and a future breaking change in any of the ten
  dependencies would go unnoticed. `renv::init()` plus a committed lockfile
  is the standard fix (`docs/reproducibility_audit.md`).
- **Commit date-stamped source snapshots.** The demand-side endpoint is
  live and unpinned, so the published figures cannot currently be
  reproduced exactly. The ERCOT JSON is CC BY 4.0 and could be committed;
  the Berkeley Lab workbook could not.
- **Add a SQL stage.** The pipeline is currently tidyverse end to end;
  moving the integration and aggregation steps into SQL against a local
  database was planned but not implemented.
- **Expand beyond one region**, which would make cross-region ranking and
  the "where" half of the research question genuinely answerable.
- **Integrate the context sources** (ERCOT GIS, EIA, NREL SLOPE, DSIRE)
  identified but not used in the current analysis.
