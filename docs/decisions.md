# Methodological Decisions Log

Every methodological decision is recorded here **before** implementation
proceeds, per `CLAUDE.md`. Format: date, decision, rationale, alternatives
considered (if any).

---

## 2026-08-15 — Primary region: ERCOT (Texas)

**Decision:** Focus the analysis on ERCOT as a single-state grid region.

**Rationale:** ERCOT has the most acute, well-documented tension between
corporate clean energy procurement demand and interconnection queue
capacity of any U.S. grid region, and its single-state scope avoids
multi-ISO/RTO comparability issues.

**Alternatives considered:** Multi-region national analysis — rejected for
this phase due to added complexity in normalizing across ISOs/RTOs with
different queue processes and reporting formats.

---

## 2026-08-15 — Core vs. secondary data sources

**Decision:** Treat Berkeley Lab "Queued Up" and ERCOT GIS reports as core
data sources driving the analysis; treat EIA, NREL SLOPE, and DSIRE as
secondary sources that enrich but don't replace the core analysis.

**Rationale:** The core sources directly measure queue/interconnection
capacity — one side of the research question. The secondary sources
provide generation-mix, technical-potential, and policy context that
inform interpretation but aren't themselves demand or capacity measures.

---

## 2026-08-15 — Raw vs. processed data separation

**Decision:** Raw source files live in `data/raw/`, are treated as
immutable, and are never edited in place; each pipeline stage writes a new
file into `data/processed/` rather than overwriting the previous stage's
output.

**Rationale:** Preserves the ability to trace any processed result back to
its raw source and re-run any pipeline stage independently; prevents
silent, unrecoverable data loss during cleaning.

---

## 2026-08-15 — Project scaffolding structure

**Decision:** Adopted the repository layout documented in `CLAUDE.md`
(`data/{raw,processed}`, `R/`, `notebooks/`, `scripts/`,
`output/{figures,tables,analysis}`, `tableau/`, `docs/`).

**Rationale:** Separates pipeline code (`R/`) from one-off fetch scripts
(`scripts/`) since they run on different cadences; separates output by
artifact type (figures/tables/analysis) to avoid mixing exploratory plots
with final deliverables; isolates the Tableau layer since dashboard logic
is not meant to be replicated in R.

---

## 2026-08-15 — ERCOT GIS report: manual download instead of automated fetch

**Decision:** Fetch the monthly ERCOT Generator Interconnection Status
(GIS) report manually (download in browser, place in
`data/raw/ercot_gis/`) rather than building an automated
`scripts/fetch_ercot_gis.R` fetch, for now.

**Rationale:** `robots.txt` on ercot.com disallows both `/misapp` (the
file-listing API, `IceDocListJsonWS?reportTypeId=15933`) and
`/misdownload` (the actual file download,
`mirDownload?doclookupId=...`). The report's public page
(`/mp/data-products/data-product-details?id=PG7-200-ER`) is itself
allowed, but it's JS-rendered and the "Available Files" list only
resolves to those two disallowed endpoints — confirmed by grepping the
page's own HTML/JS, and cross-checked against ERCOT's Oct 2022 "Decommissioning
Legacy URLs for Public Reports" notice, which confirms downloads still
route through `misdownload/servlets/mirDownload`. There is no current
public path to the file that isn't under a disallowed prefix. Separately,
no browser-automation tool (Playwright or otherwise) is currently
available in this environment, so the fetch would have needed a workaround
even absent the robots.txt issue.

**Alternatives considered:**
- ERCOT's official Developer Portal (`developer.ercot.com`) as a
  sanctioned API path — pages checked either 404'd or returned nothing, so
  it's unconfirmed whether it covers this report; would require account
  registration/API key regardless.
- Automating against the disallowed `/misapp`/`/misdownload` endpoints
  anyway — rejected per CLAUDE.md's guardrail to check `robots.txt` and
  report findings rather than route around them.

**Revisit if:** browser automation becomes available and/or the
Developer Portal is confirmed to cover this report, at which point an
automated monthly fetch could be reconsidered.

---

## 2026-08-17 — Geographic filter for Berkeley Lab queue data: use `region=='ERCOT'`, not `state=='TX'`

**Decision:** Any future filtering of the Berkeley Lab interconnection
queue data to the project's Texas/ERCOT scope must use `region=='ERCOT'`,
not `state=='TX'`.

**Rationale:** Inspection of `03. Complete Queue Data` found these are not
interchangeable: 539 rows have `state=='TX'` but `region` is `SPP`,
`MISO`, or `West` — a real geographic fact (parts of the Texas Panhandle,
El Paso area, etc. sit outside ERCOT's footprint). Using `state=='TX'`
would incorrectly pull in non-ERCOT interconnection requests. Full detail
in `docs/data_reconnaissance.md`.

**Alternatives considered:** Filtering on `state=='TX'` — rejected as
geographically inaccurate for this project's ERCOT-specific scope.

---

## 2026-08-17 — ERCOT Large Load queue sourced via ercotqueue.com (third-party), not ERCOT's primary filing directly

**Decision:** Fetch the ERCOT Large Load interconnection queue data via
`https://www.ercotqueue.com`'s public JSON API
(`/data/load/load_queue_summary.json`, `/data/load/load_projects.json`),
implemented in `R/01_import_clean.R`, rather than parsing ERCOT's LLWG
PPTX filings directly.

**Rationale:** Before writing any fetch code, verified the source is real
and legitimate rather than assuming: confirmed the domain resolves and is
live (Vercel-hosted), `robots.txt` allows `/data/load/`, both JSON
endpoints return real data, and the site explicitly states a **CC BY 4.0**
license with per-record citations to specific ERCOT LLWG "Large Load
Interconnection Status Update" report dates and slide numbers (e.g. it
discloses a slide-to-slide MW discrepancy — 8,927 vs. 8,926 — rather than
silently picking one). This is a credible, well-documented secondary
source. Parsing ERCOT's own PPTX filings directly was not attempted this
round — no browser-automation tool is available in this environment (same
limitation already logged for the GIS report), and ERCOT does not appear
to publish the LLWG deck as structured data.

**Caveat carried into the data dictionary:** the JSON is **aggregate-only**
— despite the `load_projects.json` filename, it contains 8 aggregate/
anonymized-bucket records, not a named project-level queue (ERCOT doesn't
publicly disclose one). ercotqueue.com's citations to the underlying LLWG
report have not been independently cross-checked against the original
ERCOT PPTX by this project — flagged as **[NEEDS VERIFICATION]** in
`docs/data_dictionary.md`.

**Alternatives considered:**
- Parsing ERCOT's LLWG PPTX report directly — more authoritative but not
  attempted this round given the browser-automation gap; could be
  revisited.
- Saving the raw JSON to `data/raw/ercot_gis/` as initially requested —
  rejected in favor of the dedicated `data/raw/ercot_large_load/` folder
  (created in the prior decision) to keep this demand-side source separate
  from the GIS generation-interconnection reports.

**Revisit if:** discrepancies surface between ercotqueue.com's figures and
ERCOT's original LLWG filing, or if project-level (not just aggregate)
large-load data becomes necessary for the analysis.

**Status update 2026-08-17 (same day):** `R/01_import_clean.R` remains
**unexecuted and unverified**. Samantha believed R had just been
installed locally; checked common macOS install paths (Homebrew,
`/Library/Frameworks/R.framework`, `/Applications`, Spotlight, `pkgutil`
installer receipts) and found no R/Rscript present. Do not treat the
script as validated until it's actually run — the code is grounded in the
real JSON schema (fetched and inspected directly during reconnaissance),
but has never executed in R.

---

## 2026-08-19 — Composite dataset units: `region=='ERCOT'` geography, most-recent-aligned snapshot in time

**Decision:**
- **Geographic unit:** `region == 'ERCOT'`, applied on both sides —
  Berkeley Lab filtered to `region=='ERCOT'`; ERCOT Large Load queue
  already ERCOT-scoped by construction. **Not a row-level join** — the
  composite dataset presents two independently-aggregated, ERCOT-wide
  totals in parallel, each retaining its own provenance.
- **Temporal unit:** a **snapshot alignment**. Berkeley Lab's fixed
  historical rows are filtered to the most recent point that still falls
  on or before ERCOT Large Load's current `as_of_date`. This alignment
  point is **not a fixed calendar date** — it moves forward every time
  ERCOT Large Load refreshes, so it must be re-derived from the live
  `as_of_date` each time the comparison is run, not hardcoded.

**Rationale (Samantha's):** These two units, together, best represent the
actual electricity-system operations for ERCOT — the project's chosen
focus region — at the most current point in time the data can support.
Of the options evaluated in `docs/geography_time_decision.md`:
county-level and county+year were ruled out (ERCOT Large Load discloses
no sub-ERCOT geography at all, by ERCOT's own confidentiality policy); a
merged row-level table was ruled out (aggregate-vs-project-level grain
mismatch makes it impossible without fabricating a join key). ERCOT
region + most-recent snapshot is the finest, most defensible unit both
sources can genuinely support.

**Why this matters going forward:** This decision fixes the *shape* of
the composite dataset — two parallel ERCOT-wide totals, not a merged
table — and two caveats travel with it permanently, wherever the
comparison is used:

- **Project-level vs. aggregate.** Berkeley Lab is 3,757 individual
  ERCOT-region rows, freely re-sliceable and auditable from raw data.
  ERCOT Large Load is only 8 pre-aggregated buckets (e.g. total
  submitted, approved-and-energized, by sector, by size), with **no
  underlying rows** to verify or recombine. Some buckets overlap (e.g.
  "data center sector" and "1,000+ MW size" plainly share requests) with
  no key to determine by how much — so ERCOT Large Load buckets must
  never be summed across categories, only reported as ERCOT itself
  reports them.
- **Snapshot vs. series.** Berkeley Lab's `q_date` spans 1995–2025 and
  supports a real year-over-year trend. ERCOT Large Load offers exactly
  **one current cross-section** (`as_of_date`) — its per-record dates
  (`submitted_date`, `in_service_date`) are null in every published
  record; the only populated dates (`last_seen_date`, `last_changed_date`)
  reflect ercotqueue.com's tracking cadence, not the underlying projects.
  There is currently **no demand-side historical trend** — only a supply-
  side one. Any comparison must be framed as "current state," never as
  "growth" or "change over time," on the ERCOT Large Load side.

**Practical implications:**
- Pipeline code (e.g. future `R/` scripts) must read ERCOT Large Load's
  `as_of_date` at run time and filter Berkeley Lab to that date
  dynamically — never hardcode the alignment date.
- Any table, chart, or narrative sentence presenting these two totals
  together must state both caveats above explicitly — this decision makes
  that a standing requirement, not optional framing.
- `docs/geography_time_decision.md` remains the detailed analysis behind
  this decision; this entry is the authoritative record of what was
  actually chosen.

**Alternatives considered:**
- County-level / county + year — rejected: ERCOT Large Load has no
  populated sub-ERCOT geographic field.
- A merged, row-level composite table — rejected: aggregate-vs-project-
  level grain mismatch, no shared key.
- `state == 'TX'` as the geographic unit — already rejected in the
  2026-08-17 entry above; `region=='ERCOT'` reaffirmed here as the
  standard for this project.

**Revisit if:** ERCOT or ercotqueue.com ever discloses project-level
Large Load data (would reopen county-level options), or this project
begins archiving repeated ERCOT Large Load snapshots over time (would
enable a real demand-side series instead of a single cross-section).

**Refined 2026-08-19 (same day) — operational parameters finalized:**

- **Temporal definition — cumulative-entered.** Berkeley Lab rows are
  filtered to `q_date <= ERCOT_as_of_date` only. `wd_date`/`on_date` are
  **not** used to further exclude projects withdrawn or completed before
  the snapshot date — Samantha chose the simpler "ever entered the queue
  by this date" reading over the stricter "actually still active in the
  queue on this date" reading (the latter would have needed `wd_date`,
  which is missing for 36% of withdrawn rows).
- **Hybrid capacity excluded.** Only `mw_1` counts toward the Berkeley Lab
  total. `mw_2`/`mw_3` (hybrid/co-located capacity, populated for <3% of
  rows) are not included.
- **Sector scope:**
  - *Demand side:* ERCOT Large Load's **`data_center`** bucket from
    `summary.by_sector` in `load_queue_summary.json` — chosen over
    `industrial` after checking the actual numbers: in the same snapshot
    the temporal decision anchors to (`as_of_date` 2026-06-18),
    `data_center` is 420,812 MW (90.2% of the queue) vs. `industrial` at
    just 4,665 MW (1.0%). Given the project's research question is about
    corporate demand broadly, `data_center` is the figure that actually
    captures that story.
  - **Do not use `load_projects.json`'s sector aggregates** (data_center
    158,000 / crypto 14,000 / industrial 54,000 MW) for this — those come
    from a different, older snapshot tag ("2026-01"/"2026-Q1") than the
    `as_of_date` this decision's temporal alignment anchors to, and mixing
    them in would silently break that alignment.
  - *Supply side:* Berkeley Lab's full `region=='ERCOT'` total, **not**
    filtered by `type_1`/`type_clean` (generation technology). The grid
    pools all generation to serve all load — there's no dataset-level
    correspondence between a generation technology and a load sector to
    preserve by filtering both sides to matching categories. Filtering
    supply by technology would invent a link the data doesn't support.

With this, all three parameters left open in the original entry above
are now settled — nothing further to decide before this structure can be
implemented in code.

---

## 2026-08-20 — Integrated dataset is a single snapshot row, not a time series

**Decision:** `data/processed/integrated_analysis.csv` (built by
`R/03_data_integration.R`) is **one row** — `geography == "ERCOT"`,
`time_period` a fixed label describing the cumulative-entered cutoff,
alongside `as_of_date` and the MW columns. It is **not** a multi-year
time series with one row per year.

**Rationale:** Samantha's original integration spec used the phrase
"time period" as a column and asked to "aggregate both datasets to the
agreed time unit," which could be read as wanting genuine year-by-year
rows. Berkeley Lab genuinely has ~30 years of `q_date` and could support
a real supply-side series — but ERCOT Large Load has exactly one
`as_of_date` and no per-project historical dates (confirmed:
`submitted_date`/`in_service_date` are null in every published record).
There is no demand-side historical trend to build a series from, and the
2026-08-19 decision already established this comparison must be framed
as "current state," never "growth or change over time," on the ERCOT
Large Load side. A literal multi-year table would have needed to either
repeat the one current demand figure across every historical year
(implying it was also true in the past — a fabrication) or leave it
blank for all but one row (defensible, but not what a "time period"
column implies at a glance). Confirmed directly with Samantha via a
clarifying question before writing `R/03_data_integration.R`; she chose
the single-snapshot-row reading, matching what `docs/decisions.md`
(2026-08-19) had already established.

**Alternatives considered:**
- Multi-year series with demand MW repeated across all years — rejected,
  directly contradicts the 2026-08-19 "never framed as growth or change
  over time" guardrail.
- Multi-year supply-side series + single-row demand-side figure, shown
  side by side — a real, defensible option (Berkeley Lab's data
  supports it), not chosen this round but not ruled out for a future
  supplementary view; the current composite dataset doesn't need it for
  the headline comparison.

**Revisit if:** ERCOT Large Load ever begins publishing repeated
snapshots over time (already anticipated in the 2026-08-19 decision's
"Revisit if" note) — at that point a genuine demand-side series, and a
year-by-year composite view, would become possible.

---

## 2026-08-20 — Demand Pressure Ratio and Delivery Gap MW use `active_queue_mw`, not `total_queue_mw`, as the supply base

**Decision:** In `R/04_metrics.R`, both `Demand Pressure Ratio`
(`corporate_demand_mw / active_queue_mw`) and `Delivery Gap MW`
(`corporate_demand_mw - active_queue_mw`) are computed against
`active_queue_mw` — the subset of the cumulative-entered Berkeley Lab
queue with `q_status == 'active'` — not `total_queue_mw` (the full
cumulative total including withdrawn/suspended/operational projects).

**Rationale:** withdrawn and suspended projects aren't realistically
available supply going forward; comparing current corporate demand
against only what's still actively progressing through the
interconnection queue gives the more meaningful "how much more supply is
actually needed" figure than comparing against the full historical
cumulative total, which would overstate near-term available supply.
Confirmed directly with Samantha via a clarifying question before
writing `R/04_metrics.R`.

**Standing caveat that travels with both metrics, per the existing hard
guardrail (`CLAUDE.md`):** `active_queue_mw` is still interconnection
queue MW, not deliverable MW — "active" describes queue status, not a
guarantee of eventual generation. Both metrics must always be framed as
comparisons against *potential* future generation capacity currently
progressing through the queue, never as a gap against actual or
guaranteed deliverable capacity. See `docs/metric_definitions.md` for
the full formula documentation and validation examples.

**Alternatives considered:**
- `total_queue_mw` as the base — rejected as more conservative/inclusive
  but likely to overstate realistically available near-term supply by
  including projects that have already left the queue.
- Reporting both bases as separate columns — a real, defensible option,
  not chosen this round in favor of a single, clearly-justified
  headline figure; could be revisited if Samantha wants the comparison
  later.

**Revisit if:** the "active" queue-status definition is ever refined
(e.g., a future decision to further exclude near-stalled active
projects), which would change what "available supply" means for both
metrics.

---

## 2026-08-24 — R/07_visualizations.R: real trends only where the data supports them

**Decision:** Of the 10 requested visualizations, only those built from
Berkeley Lab's actual per-project dates (`q_date`, `wd_date`) are drawn
as historical trend lines: active queue capacity over time, queue
attrition over time, and the month-over-month queue-growth chart.
Corporate demand, Demand Pressure Ratio, Delivery Gap MW, and the
Procurement Risk Score are each shown as a single labeled current-value
indicator — never plotted as a fabricated historical line — with the
current demand value additionally overlaid as a reference line on two
of the real trend charts for visual context.

**Rationale:** `integrated_analysis.csv` / `analysis_metrics.csv` /
`procurement_risk_scores.csv` are each exactly one row (this decisions
log, 2026-08-19/20) — there is no historical demand, pressure, gap, or
score data to plot a trend from. Charting them "over time" would mean
repeating today's single value across history, implying it was also
true in the past — the same fabrication risk already rejected for the
integrated dataset's shape. Confirmed directly with Samantha via a
clarifying question before writing `R/07_visualizations.R`.

**Alternatives considered:**
- Treat all 10 items as placeholders and build none of them until the
  pipeline has run repeatedly over time — rejected: Berkeley Lab's
  ~30-year `q_date`/`wd_date` history genuinely supports 3 of the 10
  charts today: building only those, honestly scoped, is more useful
  than deferring everything.
- Holding today's demand constant and dividing it into every historical
  month's queue capacity to produce a "Demand Pressure Ratio over
  time" — rejected outright: same fabrication risk as above, just one
  arithmetic step removed.

**Revisit if:** the pipeline accumulates multiple ERCOT Large Load
snapshots over time (already anticipated in the 2026-08-19 entry's
"Revisit if" note), at which point genuine demand/pressure/gap/score
trend charts would become possible.

---

## 2026-08-26 — Project renamed: "Clean Energy" dropped from the title and research question

**Decision:** The project's name and research question are changed from
"Corporate Clean Energy Demand vs. Grid Readiness" / "Where is corporate
**clean energy** demand outpacing the grid's ability to deliver it" to
**"Corporate Electricity Demand vs. Grid Interconnection Capacity"** /
"Where is corporate **electricity** demand outpacing the grid's
**interconnection capacity** to deliver it." Updated in `CLAUDE.md` and
`README.md`.

**Rationale:** `docs/analytical_critique.md` (§0, 2026-08-26) identified
that no stage of this pipeline filters either side of the core
comparison by generation technology. Supply-side capacity
(`active_queue_mw`, etc.) is Berkeley Lab's full `region=='ERCOT'` total
across every `type_1`/`type_clean` technology (gas, coal, nuclear, wind,
solar, battery, etc.) — a deliberate choice already recorded in the
2026-08-19 entry above ("the grid pools all generation to serve all
load"). Demand-side (`corporate_demand_mw`) is ERCOT Large Load's
`data_center` sector total, which carries no information at all about
whether that load intends to procure clean/renewable power specifically.
Given neither side has ever been technology-filtered, and there is no
plan to add that filtering, keeping "clean energy" in the project's name
and research question was actively misleading to anyone reading the
docs or outputs — every number this pipeline produces answers a
corporate-*electricity*-demand question, not a corporate-*clean-energy*-
demand question. Samantha confirmed: rename to match what's actually
measured rather than add technology filtering to match the old name.

**Alternatives considered:**
- **Filter Berkeley Lab supply by `type_1`/`type_clean` to renewable
  categories, and treat that as "the clean energy queue"** — technically
  possible (the field exists and is already clean), but there is still
  no equivalent filter available on the ERCOT Large Load demand side
  (no data-center-level generation-preference field is published), so
  this would only fix one side of the comparison and would still be
  misleading about the demand side specifically. Not pursued.
- **Keep the name, add a prominent caveat everywhere it appears** —
  rejected as weaker than fixing the name itself; a reader encountering
  the project title or a chart export in isolation, without the caveat
  attached, would still be misled.

**What changed as a result:** `CLAUDE.md` and `README.md` project
title/research question/example repo folder name; the `httr::user_agent()`
string in `R/01_import_clean.R`; `docs/analytical_critique.md`'s §0
finding annotated as resolved by this decision (not by adding technology
filtering). Historical entries in this file and in `docs/AI_WORKFLOW.md`
that predate this decision are left as-is — they accurately record what
was believed/decided at the time, under the project's original framing.

**Revisit if:** a demand-side generation-preference field ever becomes
available (e.g., if ERCOT or ercotqueue.com publishes it), at which
point genuinely filtering both sides to clean/renewable technology and
reintroducing a "clean energy" framing would become possible and
accurate.

---

## 2026-08-26 — Demand Pressure Ratio and Delivery Gap MW switched from `active_queue_mw` to `total_queue_mw`

**Decision:** `R/04_metrics.R`'s Demand Pressure Ratio
(`corporate_demand_mw / total_queue_mw`) and Delivery Gap MW
(`corporate_demand_mw - total_queue_mw`) now use `total_queue_mw` —
everything ever cumulatively entered the Berkeley Lab ERCOT queue,
regardless of current status — as the supply-side base. **This
supersedes the 2026-08-20 decision above**, which used `active_queue_mw`
(withdrawn/suspended/operational projects excluded).

**Rationale:** `docs/analytical_critique.md`'s robustness-check section
(recommendation #5) found that this single denominator choice, on its
own, moves the real snapshot's Demand Pressure Ratio from ~1.03 to
~0.53 — a larger swing than the entire 3-scenario weighting sensitivity
analysis (`R/06_sensitivity_analysis.R`) produced (30.0–33.5 on the
composite score). After discussing what conclusions the real numbers
support, Samantha decided directly ("I think I would like to make the
shift from active queue to total queue ever entered") that
`total_queue_mw` is the more transparent, less assumption-laden base —
it doesn't require trusting the `is_active`/`is_withdrawn`/etc. status
classification to be complete or current, just the raw cumulative-
entered total already established as this project's core temporal
definition (2026-08-19 entry above).

**Scope, confirmed via clarifying question:** metrics only.
`R/04_metrics.R`'s two formulas change; `R/05_risk_score.R` and
`R/06_sensitivity_analysis.R` are not touched directly but inherit the
new values automatically (they read `analysis_metrics.csv` by metric
name, not by formula). `R/07_visualizations.R`'s "active queue capacity"
charts (items 2, 3, 9) are explicitly left as-is — they remain a
legitimate, separate view of active-only capacity, no longer tied to
these two metrics specifically. `active_queue_mw` itself is still
computed and reported as its own pass-through metric; it isn't removed
from the pipeline, just no longer the denominator here.

**Known, not-yet-addressed downstream consequence:** `total_queue_mw` is
always ≥ `active_queue_mw` by construction, so this change systematically
lowers the Demand Pressure Ratio (and, before normalization, the
Delivery Gap MW) relative to the old formula for any snapshot.
`R/05_risk_score.R`'s `normalize_demand_pressure()` reference ceiling
(5.0x) was calibrated with no empirical basis to begin with (already
disclosed as a provisional placeholder, `docs/risk_score_design.md`) and
has **not** been re-examined in light of this change — the same
real-world pressure will now normalize to a lower component score than
it would have under the old formula, for reasons unrelated to any real
change in demand or supply. Flagged in `R/05_risk_score.R` directly;
revisiting the normalization thresholds is a separate decision, not
made here.

**Alternatives considered:** keep `active_queue_mw` (the status quo) —
rejected per the rationale above. A hybrid/two-column approach (report
both bases side by side) — not chosen this round; Samantha opted for a
single, clearly-justified headline figure, consistent with how this
same tradeoff was resolved the first time (2026-08-20 entry above).

**Revisit if:** the normalization thresholds in `R/05_risk_score.R` are
ever recalibrated (e.g., once accumulated snapshot history exists) —
that recalibration should account for this change's effect on the
Demand Pressure Ratio's scale.

---

## 2026-08-26 — Delivery Gap MW normalization rescaled to a sign-aware tanh transform

**Decision:** `R/05_risk_score.R`'s `normalize_delivery_gap()` (and its
duplicate in `R/06_sensitivity_analysis.R`) replaces the old linear
`clip_0_100((x - min_ref) / (max_ref - min_ref) * 100)` formula with
`clip_0_100(50 * (1 + tanh(x / scale)))`, `scale = 200,000` (reusing the
old linear range's ceiling value as the new scale parameter, rather than
introducing a new arbitrary number).

**Rationale:** the previous entry above (switching Delivery Gap MW to a
`total_queue_mw` base) pushed the real snapshot's value to −371,127 MW —
past the old ±200,000 MW linear range's floor. `clip_0_100()` silently
saturated that to exactly 0, destroying all magnitude information for
this component (confirmed by re-running the pipeline, not just by
hand-calculation). Samantha decided to "rescale it." Confirmed via
clarifying question which of three technical meanings that intended: a
sign-aware bounded transform (tanh), rather than simply widening the
fixed linear range or rescaling relative to `total_queue_mw`. This
matches `docs/risk_score_design.md`'s **original** recommendation for
this component specifically — "a sign-aware scaling... or a bounded
transform like tanh... since zero and negative values are meaningful,
not edge cases to exclude" — which had not been implemented when the
score was first built.

**Why this fixes the problem, not just relocates it:** a hard linear
clip has a floor/ceiling that any sufficiently extreme future value can
overshoot again, exactly as just happened. `tanh` has no such wall — it
approaches 0/100 asymptotically, so an even more extreme future gap
degrades gracefully (a very small or very large, but still
distinguishable-from-0-or-100, score) instead of flattening to a fixed
number that erases how extreme the underlying value actually is.

**What changed:** `normalize_delivery_gap()`'s signature changed from
`(x, min_ref, max_ref)` to `(x, scale)` in both `R/05_risk_score.R` and
`R/06_sensitivity_analysis.R`; `validate_risk_score_functions()`'s
hand-built checks for this function were rewritten to hand-verify the
new formula's behavior at `±scale` and at a realistic extreme value
(5× `scale`), replacing the old floor/ceiling-clipping checks that no
longer apply. `normalize_demand_pressure()` is untouched — it's flagged
as miscalibrated but not actively broken (nothing overshoots its range
today), and rescaling it wasn't part of this request.

**Alternatives considered (from the clarifying question):** widen the
fixed linear range (e.g., to ±800,000 MW) — rejected as a band-aid that
a sufficiently extreme future snapshot could overshoot again, the same
failure mode this decision is meant to close off. Rescale relative to
`total_queue_mw` (a proportional gap) — rejected as changing what the
component conceptually measures (a relative gap vs. an absolute MW
figure), a bigger conceptual shift than "rescale it" was understood to
mean.

**Revisit if:** `normalize_demand_pressure()` is ever found to have the
same active-breakage problem (it isn't, today) — the same tanh approach
would be the natural fix there too, for consistency. Also revisit the
`scale = 200,000` choice once real domain thresholds or accumulated
snapshot history exist, same as every other provisional normalization
in this file.

---

## 2026-08-28 — Tableau export uses `state_for_map = "Texas"` as a labeled map approximation for ERCOT

**Decision:** `R/09_tableau_export.R` adds a field, `state_for_map`,
hardcoded to the literal string `"Texas"`, to `data/processed/tableau_final.csv`
so the single ERCOT snapshot row can be rendered as a filled-state map in
Tableau (one of the requested dashboard use cases). This is a
**presentation-layer field only** — it does not filter, join, or derive
anything, and does not touch `region=='ERCOT'` as the pipeline's actual
geographic unit anywhere else.

**Rationale:** the Procurement Risk Score is a single ERCOT-wide
observation (n=1) — there is no multi-region data to build a real
choropleth from. Samantha confirmed (clarifying question, 2026-08-28):
add a single-state fill as the simplest way to satisfy "regional map"
from the existing dataset, over exporting a separate project-level map
(Berkeley Lab's individual queue rows, which have real county/fips
geography but no composite score) or omitting a map entirely.

**Standing caveat, given this project's own 2026-08-17 finding that
`state=='TX'` and `region=='ERCOT'` are NOT interchangeable** (539
Berkeley Lab rows sit in Texas but outside ERCOT's footprint): filling
all of Texas on a map is a **labeled visual approximation for a
single-region indicator**, not a claim that ERCOT's service territory
matches the state boundary. `tableau/README.md` states this explicitly,
and it must travel with any map built from this field — never presented
as ERCOT's precise footprint. Critically, this field is never used for
filtering or aggregation anywhere in the R pipeline — the 2026-08-17
decision's actual analytical rule (`region=='ERCOT'`, not `state=='TX'`)
is untouched.

**Alternatives considered:**
- A separate project-level Tableau export from Berkeley Lab's 4,113
  individual queue rows (real county/fips-level geography) — more
  geographically precise, but a different dataset than "the final
  analytical dataset" this request referenced, and those rows don't
  carry the composite score. Not chosen this round.
- Omitting a map entirely — rejected; a single labeled state fill,
  clearly caveated, was judged more useful than no map, given the
  dashboard is meant to include one.

**Revisit if:** ERCOT or a future source ever publishes a proper ERCOT
service-territory boundary file (shapefile/GeoJSON) that Tableau could
use instead of a state proxy, or if this pipeline ever accumulates
multiple regions to make a real choropleth possible.

---

## 2026-09-03 — `output/analysis/top_risk_regions.csv` reports 1 region, not a top-10 ranking

**Decision:** `R/10_top_risk_regions.R` writes exactly **one data row** —
the real ERCOT snapshot — to `output/analysis/top_risk_regions.csv`,
explicitly labeled via `rank`, `regions_available_in_dataset` (=1),
`regions_requested` (=10), and a `note` column, rather than fabricating
9 additional rows to fill a literal "top 10 highest-risk regions" table.

**Rationale:** Samantha asked for a top-10-regions findings table with
explicit, strongly worded constraints: do not create or invent findings,
do not speculate, only report what the data directly supports. This
pipeline's validated dataset (`data/processed/procurement_risk_scores.csv`)
contains exactly one region (ERCOT) and one snapshot — there are no other
real regions with independently computed Corporate Demand MW / Active
Queue MW / Demand Pressure / Queue Attrition / Queue Age / Delivery Gap /
Procurement Risk Score to rank; those are single ERCOT-wide composite
values by construction, not per-region figures (same structural fact
behind the 2026-08-26/28 entries above). Given the explicit "do not
invent findings" instruction, fabricating rows was never a real option.
Confirmed via clarifying question: report the 1 real region only.

**Alternatives considered:**
- Combine the 1 real row with the 9 synthetic examples from
  `output/analysis/manual_validation_sample.csv` to reach 10 rows — even
  clearly flagged, rejected as mixing synthetic and real data in a file
  whose name and purpose imply real findings, which is a real risk to
  data integrity if the file is ever excerpted without its labeling
  column.
- A different unit of analysis (e.g., individual Berkeley Lab queue
  projects instead of regions) — offered as an option; not chosen.

**Revisit if:** the pipeline ever accumulates multiple real regions
(already anticipated in the 2026-08-15 "primary region" entry's scope,
and the 2026-08-19 entry's geographic-unit discussion) — at that point a
genuine top-10 ranking becomes possible and this script should be
revisited to produce one.

---

## 2026-09-09 — Commit the demand-side raw snapshot; make `R/01`'s fetch conditional

**Decision:** commit a date-stamped copy of the two ERCOT Large Load JSON
files at `data/raw/ercot_large_load/snapshot_2026-06-18/`, and change
`R/01_import_clean.R` so the fetch does not overwrite an existing raw file
unless explicitly asked to refresh.

**Rationale:** two problems that compound each other.

The `as_of_date` **2026-06-18** anchors every published figure in this
project — 420,812 MW of demand, 791,938.89 MW of total queue, the 0.32
attrition rate, the score of 21.03, all eleven figures, and the Tableau
export. That snapshot existed in exactly one place: two gitignored files
totalling 12.5 KB, with no backup.

Meanwhile `R/01` re-downloaded and overwrote both files unconditionally on
every run (HIGH-3 in `docs/final_code_review.md`), from a live endpoint
whose `as_of_date` advances as ERCOT publishes new Large Load Working
Group reports. A single re-run would have replaced the analysis input with
a different snapshot, unrecoverably, and silently — while contradicting
this project's own immutability rule (`docs/decisions.md`, 2026-08-15:
raw source files "are treated as immutable, and are never edited in
place").

The risk became concrete when `README.md` gained a Getting started section
on 2026-09-08 instructing a reader to run `R/01` first.

Committing the snapshot is permitted: ercotqueue.com's data is licensed
**CC BY 4.0**, which explicitly allows redistribution with attribution.
Attribution is carried in the snapshot's own README and in
`R/01_import_clean.R`'s header. At 12.5 KB there is no size argument
against it. This also closes finding 5.2 in
`docs/github_release_checklist.md` and materially improves the
demand-side half of `docs/reproducibility_audit.md`.

**Deliberately narrow scope:** the committed snapshot is a **copy** at a
separate path that no script reads or writes. `R/01` continues to read and
write `data/raw/ercot_large_load/` exactly as before. Nothing about the
analysis, the cleaning logic, or any published number changes — this
protects the input and does not touch the pipeline's behaviour beyond the
refresh guard.

**Alternatives considered:**
- **Date-stamped filenames written by `R/01` itself**
  (`load_queue_summary_2026-06-18.json`), as `docs/final_code_review.md`
  suggests. Better long-term, and the right shape if repeated snapshots
  ever become real future work — but it changes the paths `R/01` reads,
  which is a larger change to validated code than the problem requires
  today. Left as future work.
- **Back the files up outside the repository.** Protects the snapshot but
  does nothing for reproducibility, and an uncommitted backup is the kind
  of thing that is lost in a year.
- **Commit the Berkeley Lab workbook too**, for symmetry. Rejected: at
  15 MB it is a third party's research dataset whose redistribution terms
  are LBNL's to set, and committing it would answer that question
  implicitly. `data/README.md` documents how to obtain it instead.
- **Leave `R/01` alone and rely on the committed copy.** Rejected: the
  copy would survive, but a re-run would still silently swap the working
  snapshot, so every subsequent output would describe a different
  `as_of_date` than the documentation claims.

**Refined the same day, after `/code-review`:** the first version of this
change guarded only *existing* files, which meant it never fired on a
fresh clone — exactly the case `README.md` "Getting started" walks a new
reader through. The committed snapshot would have sat inert while `R/01`
downloaded a live, newer one. Three further defects came out of the same
review. The implemented behaviour is therefore:

1. **Seed from the committed snapshot** when the working file is absent,
   so a fresh clone reproduces the published demand-side figures by
   default rather than silently analysing a different date.
2. **Honour `ERCOT_LARGE_LOAD_REFRESH` as an environment variable**, not
   only as an R global. `exists()` does not see environment variables, so
   `ERCOT_LARGE_LOAD_REFRESH=TRUE Rscript R/01_import_clean.R` — the
   invocation `README.md` documents — would have silently resolved to
   `FALSE` and reported success while reusing the stale file.
3. **Validate that a reused or downloaded file parses as JSON.** With
   re-downloading off by default, a truncated download or a saved HTTP
   error page would otherwise be cached indefinitely, producing a
   recurring parse error that re-running could not clear. Downloads now
   write to a `.part` file and `file.rename()` into place, so an
   interrupted run cannot leave damage behind.
4. **Warn after the HTTP request succeeds**, not before it. The first
   version warned that the anchor snapshot had been destroyed even when
   the request failed and the file was never touched.

**Revisit if:** the project ever accumulates repeated snapshots (the first
item under "Future work" in `README.md`), at which point date-stamped
filenames written directly by `R/01` become the better design and this
copy-based approach should be replaced.
