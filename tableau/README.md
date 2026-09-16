# Tableau Dashboard — Data Guide

## What dataset to use

**`data/processed/tableau_final.csv`** — the only file the three
dashboards (see `tableau/dashboard_design.md`) should connect to, with
one sanctioned exception noted below. It is produced by
`R/09_tableau_export.R`, which
computes nothing new itself; every value (except `state_for_map`, see
below) is a direct pass-through of a number already derived and
validated by `R/03_data_integration.R`, `R/05_risk_score.R`, or
`R/06_sensitivity_analysis.R`.

**This file is exactly one row.** It represents a single ERCOT-wide
snapshot at one point in time (`as_of_date`) — not a time series, not a
multi-region table. That shape is intentional, not a placeholder:
Berkeley Lab's demand-side counterpart (ERCOT Large Load) publishes
exactly one current cross-section with no per-project historical dates
(`docs/decisions.md`, 2026-08-19/20/24). Any dashboard element implying
a trend over time or a comparison across regions would be fabricating
data this pipeline doesn't have — build single-value indicators instead
(see Recommended calculated fields, below).

**One sanctioned secondary connection:** the Drivers of Risk dashboard's
sensitivity range chart (see `tableau/dashboard_design.md`, Dashboard 3)
connects to `output/analysis/risk_score_sensitivity.csv` directly,
instead of re-pivoting `tableau_final.csv`'s flattened `sensitivity_*`
columns — that file is already tidy long-format (one row per weighting
scenario), which is simpler for that one chart. Every other chart on all
three dashboards should still connect only to `tableau_final.csv`.

## Field definitions

| Field | Meaning | Unit | Source |
|---|---|---|---|
| `geography` | Region this snapshot covers | text | `integrated_analysis.csv` |
| `state_for_map` | Literal `"Texas"` — a map-rendering field only, **not** an exact ERCOT boundary. See "Map caveat" below. | text | added by `R/09` |
| `time_period` | Description of the cumulative-entered cutoff this snapshot covers | text | `integrated_analysis.csv` |
| `as_of_date` | The snapshot's anchor date | date | `integrated_analysis.csv` |
| `corporate_demand_mw` | ERCOT Large Load `data_center` sector demand, as-of snapshot | MW | `integrated_analysis.csv` |
| `total_queue_mw` | Everything ever cumulatively entered the Berkeley Lab ERCOT interconnection queue, any status | MW | `integrated_analysis.csv` |
| `active_queue_mw` | Subset of the above still `q_status == 'active'` | MW | `integrated_analysis.csv` |
| `withdrawn_queue_mw` | Subset of the above `q_status == 'withdrawn'` | MW | `integrated_analysis.csv` |
| `n_projects_in_scope` | Count of Berkeley Lab ERCOT projects in scope for this snapshot | count | `integrated_analysis.csv` |
| `demand_pressure_ratio` | `corporate_demand_mw / total_queue_mw` | ratio | `procurement_risk_scores.csv` |
| `delivery_gap_mw` | `corporate_demand_mw - total_queue_mw` | MW | `procurement_risk_scores.csv` |
| `queue_attrition_rate` | `withdrawn_queue_mw / total_queue_mw` — a cumulative, pooled 30-year ratio, not a cohort rate | ratio [0,1] | `procurement_risk_scores.csv` |
| `queue_age_days` | MW-weighted median days since queue entry, active projects only | days | `procurement_risk_scores.csv` |
| `n_active_projects_for_queue_age` | Sample size behind `queue_age_days` | count | `procurement_risk_scores.csv` |
| `norm_demand_pressure` | Demand Pressure Ratio, normalized to 0–100 | score | `procurement_risk_scores.csv` |
| `norm_delivery_gap` | Delivery Gap MW, normalized to 0–100 (sign-aware tanh transform) | score | `procurement_risk_scores.csv` |
| `norm_queue_attrition` | Queue Attrition Rate, normalized to 0–100 | score | `procurement_risk_scores.csv` |
| `norm_queue_age` | Queue Age, normalized to 0–100 | score | `procurement_risk_scores.csv` |
| `procurement_risk_score` | Weighted composite of the four normalized components above | score, 0–100 | `procurement_risk_scores.csv` |
| `excluded_components` | Any component excluded from this run's composite (NA today) | text | `procurement_risk_scores.csv` |
| `weights_used` | The actual weights applied to compute the composite, formatted for display (rescaled if any component was excluded) | text | `procurement_risk_scores.csv` |
| `weight_demand_pressure`, `weight_delivery_gap`, `weight_queue_attrition`, `weight_queue_age` | The same weights as `weights_used`, as four separate numeric fields — use these in calculated fields; `weights_used` is for display only, since Tableau has no clean way to parse its formatted string | ratio, sum to 1 | `risk_score_sensitivity.csv` (base_case row) |
| `sensitivity_score_demand_pressure_heavy`, `sensitivity_score_queue_risk_heavy` | The composite score under two alternative, equally defensible weighting scenarios (60/40 demand-heavy; 20/80 queue-heavy) — `procurement_risk_score` above is the base-case scenario's score | score, 0–100 | `risk_score_sensitivity.csv` |
| `sensitivity_score_vs_base_demand_pressure_heavy`, `sensitivity_score_vs_base_queue_risk_heavy` | How much each alternative scenario's score differs from the base case | score points | `risk_score_sensitivity.csv` |
| `sensitivity_primary_driver_demand_pressure_heavy`, `sensitivity_primary_driver_queue_risk_heavy` | Which component's weighted contribution moved the most in each alternative scenario | text | `risk_score_sensitivity.csv` |

**Why the sensitivity fields are here at all:** CLAUDE.md's hard guardrail
requires the Procurement Risk Score to always be shown "with its
weighting scheme and sensitivity results alongside it, never as a bare
ranking." A dashboard that shows only `procurement_risk_score` and
`weights_used` satisfies the first half of that but not the second —
these six fields exist so a sheet or tooltip can show how much the score
moves under different reasonable weightings without needing a second
data source. See `docs/risk_score_sensitivity_interpretation.md` for the
full narrative interpretation.

Full formula definitions and normalization rationale:
`docs/metric_definitions.md`, `docs/risk_score_design.md`,
`docs/risk_score_sensitivity_interpretation.md`.

## Recommended dimensions

- `geography`
- `state_for_map`
- `time_period`
- `as_of_date`

## Recommended measures

- `corporate_demand_mw`, `total_queue_mw`, `active_queue_mw`, `withdrawn_queue_mw`
- `demand_pressure_ratio`, `delivery_gap_mw`, `queue_attrition_rate`, `queue_age_days`
- `norm_demand_pressure`, `norm_delivery_gap`, `norm_queue_attrition`, `norm_queue_age`
- `procurement_risk_score`
- `weight_demand_pressure`, `weight_delivery_gap`, `weight_queue_attrition`, `weight_queue_age`
- `sensitivity_score_demand_pressure_heavy`, `sensitivity_score_queue_risk_heavy`,
  `sensitivity_score_vs_base_demand_pressure_heavy`, `sensitivity_score_vs_base_queue_risk_heavy`

## Recommended calculated fields (build these in Tableau — don't re-derive them in R)

- **Guardrail caption** — a fixed-text calculated field (not derived from
  the data) for use in a tooltip or footer on any sheet showing MW
  figures or the risk score:
  > "Interconnection queue MW is potential future capacity, not
  > deliverable MW. The Procurement Risk Score is an analytical
  > construct reflecting a specific weighting scheme, not objective
  > truth — see the weights and sensitivity scenarios alongside it."
  This isn't optional decoration — it's the standing guardrail from this
  project's `CLAUDE.md`, and it should travel with the score wherever
  it's shown.
- **Component contribution** — `[norm_X] * [weight_X]` for each of the
  four normalized components, using the numeric `weight_*` fields (not
  `weights_used`, which is a formatted string). Useful for a stacked bar
  showing what's actually driving `procurement_risk_score`.
- **Sensitivity range/tornado chart** — plot `procurement_risk_score`
  alongside `sensitivity_score_demand_pressure_heavy` and
  `sensitivity_score_queue_risk_heavy` as three bars or a range, per the
  guardrail above — this is the "sensitivity results alongside it"
  CLAUDE.md requires, not an optional extra chart.
- **Snapshot label** — `"ERCOT snapshot as of " + STR([as_of_date])`, for
  chart titles — a reminder to the viewer that every number on the
  dashboard is a single point in time, not a trend.

## Map caveat — read before building the Regional Risk dashboard's map

`state_for_map` is a **labeled visual approximation**, not a real ERCOT
boundary file. This pipeline's actual geographic filter, used everywhere
else, is `region == 'ERCOT'` — and this project already found
(`docs/decisions.md`, 2026-08-17) that `state == 'TX'` and
`region == 'ERCOT'` are **not** interchangeable: 539 Berkeley Lab rows
sit in Texas but outside ERCOT (parts of the Panhandle, El Paso area,
etc. are on other grids). Filling the entire state of Texas on a map is
a stand-in for a single-region indicator with no better geographic asset
available — never caption it as ERCOT's precise service territory. If
these dashboards need a more accurate boundary later, that requires a
real ERCOT service-territory shapefile/GeoJSON, which this project does
not currently have (see `docs/decisions.md`, 2026-08-28 entry).
