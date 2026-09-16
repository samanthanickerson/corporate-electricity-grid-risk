# Tableau Dashboard Narrative — 3-Dashboard Structure

Companion to `tableau/README.md` (field definitions, source columns).
This document is the build spec for three linked dashboards designed to
answer the research question — *"Where is corporate electricity demand
outpacing the grid's interconnection capacity to deliver it, and by how
much?"* — within roughly two minutes of exploration:

1. **Executive Overview** — the headline answer (~30 sec)
2. **Regional Risk** — geographic/regional context (~40 sec)
3. **Drivers of Risk** — methodology transparency (~50 sec)

**Every chart, KPI, and filter below is built from data already produced
and validated in this pipeline** — `data/processed/tableau_final.csv`
and `output/analysis/risk_score_sensitivity.csv`. Nothing here introduces
a new number, a new region, or a new finding; this document only
arranges what already exists into a narrative.

## The constraint every dashboard is designed around

This pipeline has **one snapshot, one region (ERCOT)**. No dashboard
below implies a trend over time or a comparison across regions — where a
name might suggest otherwise (see Dashboard 2), the dashboard says so
explicitly, first, before anything else. No chart uses a discrete
High/Medium/Low risk tier: the real snapshot's `procurement_risk_score`
(21.0) falls in the gap between the illustrative validation sample's
synthetic Low (7.3–17.2) and Medium (35.4–42.4) bands — concrete
evidence those bands were never calibrated cutoffs. Every component
score is shown on a **continuous** scale.

**The guardrail this request specifically flagged:** interconnection
queue MW is potential future capacity currently sitting in the queue —
never phrased, anywhere on any dashboard, as guaranteed, delivered, or
actual generation. Every subtitle and footer below carries a version of
this explicitly; it is not left to a single disclaimer buried in one
tooltip.

## Data sources

- **Primary, Dashboards 1 & 2, plus Dashboard 3's KPI tiles:**
  `data/processed/tableau_final.csv` (one row).
- **Secondary, both of Dashboard 3's charts:**
  `output/analysis/risk_score_sensitivity.csv` (one row per weighting
  scenario — already tidy long-format). This is a correction from this
  design's first draft: the component-breakdown chart needs per-scenario
  *weights*, which only exist in this file, not in `tableau_final.csv`
  (which carries only the base_case weights). So both of Dashboard 3's
  charts — component breakdown and the sensitivity tornado — use this
  file; `tableau_final.csv` supplies only that dashboard's 3 KPI tiles.
  See `tableau/README.md` for why this is the one sanctioned exception to
  "connect only to tableau_final.csv."
- Dashboard 1's demand-vs-supply bar chart compares several measures
  from one wide row side-by-side — build it with Tableau's built-in
  **Measure Names / Measure Values** shelf fields (drag Measure Values
  to the chart, drag Measure Names to Filter and keep only
  `corporate_demand_mw`/`total_queue_mw`), not a data-source Pivot —
  simpler, and doesn't require reshaping the connection itself. Don't add
  pre-shaped CSVs to the R pipeline for this — CLAUDE.md says not to
  replicate dashboard logic in R.

---

## Dashboard 1 — Executive Overview

**Purpose:** answer the research question at a glance, before any
drill-down. A viewer who only sees this one dashboard should still walk
away with the right headline number and the right caveat.

**Title:** "Corporate Electricity Demand vs. Grid Interconnection
Capacity — ERCOT Snapshot"

**Subtitle:** "ERCOT snapshot as of **[as_of_date]** — a single
point-in-time comparison, not a trend. Interconnection queue MW is
potential future capacity currently in the queue, not guaranteed or
delivered generation."

### KPI tiles (top row, 4 across)

| Tile | Field | Format |
|---|---|---|
| Corporate Demand | `corporate_demand_mw` | MW, thousands separator, 0 decimals |
| Total Queue Capacity | `total_queue_mw` | MW, thousands separator, 0 decimals |
| Delivery Gap | `delivery_gap_mw` | Signed MW; label reads "Total queue capacity **exceeds** demand by X MW" when negative, "Demand **exceeds** total queue capacity by X MW" when positive — never just a bare signed number |
| Procurement Risk Score | `procurement_risk_score` | 0–100, 1 decimal |

### Charts

**1. Demand vs. Total Queue Capacity (primary, largest chart on the
page)** — grouped bar, `corporate_demand_mw` vs. `total_queue_mw`
(Pivot these two columns into long format). This bar chart *is* the
answer to the research question — put it directly under the KPI row,
full width.
- Subtitle on the chart itself: "Total queue capacity currently exceeds
  corporate demand at this snapshot — see Dashboard 2 for the regional
  view and Dashboard 3 for what drives risk beyond this raw comparison."
  (Edit the direction if the underlying numbers ever flip.)

**2. Procurement Risk Score — big number with a condensed sensitivity
strip** — the score as a large number (reuse the KPI tile's value, shown
larger here as a focal point), with three small marks beneath it for
`base_case` / `demand_pressure_heavy` / `queue_risk_heavy` scores from
`risk_score_sensitivity.csv` (a compact 3-dot or 3-bar strip, not the
full tornado chart — that's Dashboard 3's job). This keeps the "not
objective truth, see weighting" guardrail visible on the very first
dashboard, not just the last one.
- Caption: "Composite score under 3 different, equally defensible
  weighting choices. Full breakdown: Drivers of Risk dashboard."

### Filters

**None.** State this explicitly in a small note near the header (e.g.,
"This snapshot has no filterable dimensions — one region, one point in
time") rather than leaving a viewer to wonder why there's no filter
pane, which is the expected UI pattern on a Tableau dashboard.

### Tooltips

- Every mark showing an MW value: the guardrail caption — "Interconnection
  queue MW is potential future capacity, not deliverable or guaranteed
  MW."
- Risk score big number: weighting scheme in one line (e.g.,
  "demand_pressure=1/6, delivery_gap=1/6, queue_attrition=1/3,
  queue_age=1/3") + "See Drivers of Risk for the full breakdown."

### Recommended order of visuals

Header/subtitle → KPI tile row → demand-vs-supply bar chart → risk score
+ condensed sensitivity strip → footer/navigation strip.

---

## Dashboard 2 — Regional Risk

**Purpose:** ground the headline number geographically, and be explicit
about what "regional" does and doesn't mean here before anything else on
the page.

**Title:** "ERCOT Regional Risk Profile"

**Subtitle (read this first, by design):** "This analysis covers **ERCOT
(Texas) only** — the single U.S. grid region measured in this dataset.
No cross-region comparison is available or implied. The map below
approximates ERCOT's footprint using the Texas state boundary — ERCOT's
actual service territory is not identical to the state line (see
`tableau/README.md`'s Map caveat)."

### KPI tiles (regional indicator panel, beside or below the map)

| Tile | Field | Format |
|---|---|---|
| Corporate Demand | `corporate_demand_mw` | MW |
| Active Queue Capacity | `active_queue_mw` | MW |
| Withdrawn Queue Capacity | `withdrawn_queue_mw` | MW |
| Queue Attrition Rate | `queue_attrition_rate` | Percent, 1 decimal |
| Queue Age (median) | `queue_age_days` | Days, 0 decimals, with `n_active_projects_for_queue_age` as a small "based on N active projects" caption |

### Chart

**1. ERCOT/Texas filled map (primary chart)** — `state_for_map` on the
geographic role, colored by `procurement_risk_score` on a **continuous**
sequential scale (never a discrete tier — see the constraint at the top
of this document).

**Recommended interactivity — a color-by parameter, not a fabricated
filter:** add a Tableau parameter letting the viewer swap what the map's
fill encodes, among three fields that already exist:
`procurement_risk_score`, `demand_pressure_ratio`, `queue_attrition_rate`.
This is what gives this dashboard genuine "exploration" within the
2-minute goal without inventing any new dimension — a viewer can
actually change what they're looking at and see a different number,
using only real, already-validated fields.

### Filters

None in the traditional sense — n=1 leaves nothing to filter by row. The
color-by parameter above is this dashboard's interactive element instead
of a filter pane.

### Tooltips

Map tooltip shows the full regional KPI panel (all 5 fields above) +
the guardrail caption + the map-approximation caveat restated briefly
("Texas boundary shown; not ERCOT's exact footprint").

### Recommended order of visuals

Header/subtitle (scope statement, first and unavoidable) → map → regional
KPI panel → color-by parameter control → footer/navigation strip.

---

## Dashboard 3 — Drivers of Risk

**Purpose:** explain *why* the score is what it is — the
methodology-transparency dashboard a viewer reaches after trusting the
headline number and wanting to know what's behind it.

**Title:** "What's Driving the Procurement Risk Score"

**Subtitle:** "Four weighted components combine into the composite score
below. This score reflects a **chosen weighting scheme, not an objective
ranking** — the scenarios further down show how much it moves under two
other equally defensible weightings. Normalization thresholds for three
of the four components are provisional placeholders, not empirically
calibrated (see `docs/risk_score_design.md`)."

### KPI tiles

| Tile | Field | Format |
|---|---|---|
| Procurement Risk Score | `procurement_risk_score` | 0–100, 1 decimal — repeated here as the anchor the rest of the page explains |
| Queue Attrition Rate (normalized) | `norm_queue_attrition` | 0–100 — currently the largest normalized driver |
| Queue Age (days) | `queue_age_days` | Days, 0 decimals |

### Charts

**1. Component breakdown bar** — the four `norm_*` fields
(`norm_demand_pressure`, `norm_delivery_gap`, `norm_queue_attrition`,
`norm_queue_age`), 0–100 axis. Label each bar with its weighted
contribution (`[Normalized Score] × [matching weight_* field]`, e.g.
"32.0 × 1/3 = 10.7") so the connection between a component's raw score
and its actual pull on the composite is visible, not just implied.

**Data source correction (2026-08-31):** this chart must be built from
`output/analysis/risk_score_sensitivity.csv`, **not** `tableau_final.csv`.
`tableau_final.csv` only carries the base_case scenario's weights — there
is no per-scenario weight data in the wide export for a selector to
switch between. `risk_score_sensitivity.csv` already has both `norm_*`
and `weight_*` for all 3 scenarios in one long table, which is what the
scenario selector below actually needs.

**Real interactive filter — a scenario selector, not a fabricated
one:** a standard Tableau filter on the `scenario` field itself (already
a real dimension in `risk_score_sensitivity.csv` — no parameter needed),
applied to this worksheet only, swapping which scenario's `weight_*`
values drive the contribution labels on this chart. Note that `norm_*`
is identical across all 3 scenarios (only the weights and resulting
composite differ) — the bars themselves won't move as the filter
changes, only the weighted-contribution labels and the composite score
will. That's not a bug to fix; it's the actual, real finding this
interaction is meant to surface — worth stating on the chart itself
(e.g., a caption: "Bar heights don't change with scenario — only how
much each one counts toward the score does"). This is real, not
invented: it's literally the sensitivity analysis R/06 already ran, made
interactive.

**2. Sensitivity range / tornado chart (full version)** — one mark per
scenario (`base_case`, `demand_pressure_heavy`, `queue_risk_heavy`) on
`procurement_risk_score`, from `risk_score_sensitivity.csv`. Label each
with `primary_driver` (which component moved the most in that scenario's
deviation from base case) and `score_vs_base`. This chart is the direct,
required answer to CLAUDE.md's hard guardrail — it must be on this page,
not hidden behind a click.

### Filters

The scenario selector described under Chart 1, above — the only real
filterable dimension anywhere in this dataset (3 named weighting
scenarios), used exactly where it's meaningful.

### Tooltips

- Component bars: a one-line formula pointer (e.g., "Demand Pressure
  Ratio = corporate demand ÷ total queue capacity — see
  `docs/metric_definitions.md`") plus "normalization threshold:
  provisional placeholder" where applicable.
- Sensitivity marks: `score_vs_base` and `primary_driver`, plus a repeat
  of "this score depends on the weighting scheme chosen."

### Recommended order of visuals

Header/subtitle → risk score anchor KPI → component breakdown bar with
scenario selector → sensitivity tornado chart → footer/navigation strip
(fullest version of the guardrail caption belongs here, including the
provisional-thresholds caveat that doesn't need repeating on the other
two dashboards).

---

## Cross-dashboard navigation

Add a small navigation strip (Tableau "navigate" dashboard actions) to
every dashboard — Executive Overview → Regional Risk → Drivers of
Risk — so the intended ~2-minute path is a guided sequence a viewer can
follow in order, not three disconnected tabs they have to discover on
their own.

## What not to build (unchanged from the prior single-page design)

- No trend line or "over time" chart anywhere in these three dashboards
  — there is exactly one snapshot. (Real multi-year supply-side history
  exists in `data/processed/queued_up_clean.csv` and is already charted
  statically in `R/07_visualizations.R`; if a future dashboard adds a
  real trend view, it should source from there directly, not imply a
  demand or risk-score trend that doesn't exist.)
- No cross-region ranking or comparison chart — ERCOT is the only region
  in this dataset; Dashboard 2 says so explicitly rather than implying
  otherwise through its name alone.
- No discrete risk-tier badge or bucket, anywhere.
- No pre-pivoted CSVs added to the R pipeline for Tableau's convenience —
  use Tableau's own Pivot transform, and the scenario/color-by parameters
  described above, instead.

## How this evolves

Unchanged from `docs/decisions.md`'s existing "revisit if" language
(2026-08-19/20/24 entries): if the pipeline ever accumulates multiple
ERCOT Large Load snapshots over time, a genuine demand/pressure/gap/score
trend becomes possible, and a fourth dashboard (or a redesigned
Executive Overview) could add it then — not before.
