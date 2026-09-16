# Procurement Risk Score — Sensitivity Analysis Interpretation

Companion interpretation for `output/analysis/risk_score_sensitivity.csv`
and `output/figures/risk_score_sensitivity.png`, produced by
`R/06_sensitivity_analysis.R`.

**Updated 2026-08-25 — the pipeline has now actually run.** R and all
required packages were installed and `R/01` through `R/07` executed
end to end for the first time. The "What this analysis can and can't
answer" and "How to read the results" sections below were written
before execution and are kept as-is (the scope limits they describe
still hold exactly). The **Results** section below reports the real
numbers, with no interpretation added. The **Conclusion** section at
the end is a placeholder for Samantha's own analysis.

**Updated again 2026-08-26** — the Results section's numbers were
regenerated after Samantha changed Demand Pressure Ratio/Delivery Gap
MW to use `total_queue_mw` instead of `active_queue_mw`
(`docs/decisions.md`, 2026-08-26). This changed the headline numbers
substantially and surfaced a normalization defect (Delivery Gap MW
saturating to exactly 0).

**Updated a third time, same day** — that defect is now fixed.
`normalize_delivery_gap()` was rescaled from a hard linear clip to a
sign-aware `tanh` transform (`docs/decisions.md`, 2026-08-26, second
entry), and the pipeline re-run again. The Results section below
reflects this final, rescaled state.

## What this analysis can and can't answer

The original request asked which **time periods** remain consistently
high-risk, which are sensitive to weighting, and what that means for
reliability. As confirmed with Samantha (2026-08-24), the pipeline
currently contains **exactly one region (ERCOT) and one snapshot** — so
those questions, taken literally, aren't answerable yet:

- **"Which time periods remain consistently high-risk"** — not
  answerable. There is exactly one time period. This becomes answerable
  once the pipeline has been run repeatedly over time (e.g., monthly),
  producing multiple snapshot rows to compare.
- **"Rank correlation between scenarios"** and **"top 10 highest-risk
  regions"** — not answerable. Both require multiple ranked entities;
  there is one region.

What **is** answerable, and what this analysis actually does: how much
does ERCOT's single Procurement Risk Score move when the weighting
scheme changes, and which component drives that movement? That's a real,
meaningful test of the score's sensitivity — just not a ranking.

## How to read the results (fill in after running `R/06_sensitivity_analysis.R`)

`output/analysis/risk_score_sensitivity.csv` has one row per scenario
(`base_case`, `demand_pressure_heavy`, `queue_risk_heavy`), each with the
resulting `procurement_risk_score`, `score_vs_base`, and `primary_driver`
(which component's weighted contribution changed the most from base).

- **If `score_vs_base` is large for both alternative scenarios** (the
  score swings substantially whether demand-side or queue-side emphasis
  increases): the composite score is highly sensitive to the weighting
  choice — a genuinely subjective methodological decision, not something
  derived from the data itself. This is evidence *for* treating the
  score cautiously, not as a settled ranking.
- **If `score_vs_base` is small for both**: the score is comparatively
  stable to this particular axis of weighting variation — worth noting,
  but not proof the score is "objectively correct," since both
  scenarios still use the same provisional normalization thresholds
  (`docs/risk_score_design.md`), which are a separate, unaddressed
  source of uncertainty (see below).
- **`primary_driver`** identifies which single component is doing the
  most work in each scenario's deviation from base — useful for knowing
  which underlying number (Demand Pressure Ratio, Delivery Gap MW, Queue
  Attrition Rate, or Queue Age) the score is most sensitive to, and
  therefore which one most deserves scrutiny or better data before the
  score is trusted.

## Results

**Updated 2026-08-26 — Demand Pressure Ratio and Delivery Gap MW now use
`total_queue_mw`, not `active_queue_mw`** (`docs/decisions.md`,
2026-08-26, superseding the 2026-08-20 decision). Samantha chose this
switch after reviewing `docs/analytical_critique.md`'s robustness-check
finding that the active-vs-total choice alone swings the Demand Pressure
Ratio more than the entire weighting sensitivity analysis below. The
numbers in this section are from the pipeline's second real execution,
under the new formula — the 2026-08-25 numbers this section originally
reported (Demand Pressure Ratio 1.03, Delivery Gap +13,400 MW,
Procurement Risk Score 31.2) are superseded and no longer reflect what
the pipeline currently computes.

**Underlying snapshot** (`data/processed/procurement_risk_scores.csv`,
ERCOT, `as_of_date` 2026-06-18):

| Raw value | Amount |
|---|---:|
| Corporate Demand | 420,812 MW |
| Total Queue Capacity (all statuses, ever entered) | 791,939 MW |
| Active Queue Capacity (reported separately; no longer the ratio/gap base) | 407,412 MW |
| Demand Pressure Ratio (demand ÷ total queue) | 0.53 |
| Delivery Gap (demand − total queue) | −371,127 MW |
| Queue Attrition Rate | 0.32 |
| Queue Age (MW-weighted median) | 897 days (n = 1,760 active projects) |

**The sign flipped, not just the magnitude:** under the old
active-queue-based formula, demand slightly *exceeded* supply
(+13,400 MW). Under the new total-queue-based formula, supply vastly
*exceeds* demand (−371,127 MW) — because `total_queue_mw` includes
every project ever entered, including the ~253,000 MW already withdrawn
and ~94,000 MW already operational, not just what's currently active.

**Normalized components (0–100) and base-case composite score:**

| Component | Normalized score |
|---|---:|
| Queue Attrition | 32 |
| Queue Age | 25 |
| Demand Pressure | 11 |
| Delivery Gap | 2.4 |
| **Procurement Risk Score (base case)** | **21.0** |

**Delivery Gap's normalization was rescaled the same day** (`docs/decisions.md`,
2026-08-26, second entry). The linear ±200,000 MW clip that produced an
exact `0` above (documented in this doc's prior revision, and flagged as
actively broken in `R/05_risk_score.R`'s code) has been replaced with a
sign-aware `tanh` transform (`50 × (1 + tanh(gap / 200,000))`) that
approaches, but never hard-clips to, 0 or 100. −371,127 MW now
normalizes to **2.4**, not 0 — small, correctly reflecting that total
queue capacity vastly exceeds demand, but no longer erasing the
magnitude entirely. The composite score above (21.0) is the real,
current pipeline output under this fix.

No components are excluded in this run (`excluded_components` is blank
in both output files).

**Sensitivity across the 3 weighting scenarios**
(`output/analysis/risk_score_sensitivity.csv`):

| Scenario | Score | score_vs_base | primary_driver | contribution change |
|---|---:|---:|---|---:|
| Base case | 21.0 | — | — | — |
| Demand-pressure-heavy (60/40) | 15.2 | −5.8 | queue_attrition | −4.3 |
| Queue-risk-heavy (20/80) | 23.9 | +2.9 | queue_attrition | +2.1 |

**`primary_driver` is `queue_attrition` in both alternative scenarios**,
same as it was immediately after the saturation bug (before the rescale
above) — this is *not* an artifact of that bug, since Delivery Gap no
longer contributes a fixed, weight-independent `0`. It reflects that in
these 3 scenarios, the demand-side pair (Demand Pressure + Delivery Gap)
and the queue-side pair (Attrition + Age) always move together by
construction (§12 of `docs/analytical_critique.md`), and Queue
Attrition's own normalized score (32) is currently larger than Delivery
Gap's (2.4) — so a percentage-point shift in the queue-side pair's
combined weight moves the total score more than the same shift in the
demand-side pair's weight would.

**Relevant figures:**
- `output/figures/risk_score_sensitivity.png` — the 3-scenario bar
  chart with the base-case reference line (from `R/06`).
- `output/figures/risk_score_component_comparison.png` — the 4
  normalized components for this snapshot, ranked (from `R/07`).
- `output/figures/procurement_risk_score_snapshot.png` — the single
  current composite score (from `R/07`).
- `output/figures/demand_vs_queue_scatter.png` — still plots demand vs.
  **active** queue capacity specifically (a separate, intentionally-
  retained view per `docs/decisions.md`'s 2026-08-26 scope note), so its
  ~1.03 ratio visual is not stale — it was never based on the metric
  that changed.
- `output/figures/demand_vs_active_queue_over_time.png` and
  `output/figures/active_queue_capacity_over_time.png` — likewise
  unaffected; both intentionally chart active-only capacity as a
  separate view, not the Demand Pressure Ratio/Delivery Gap MW metrics.

## What this means for the score's reliability

Regardless of the specific numbers: the fact that this analysis exists
and produces *different* scores under three defensible weighting choices
is itself the point. **The Procurement Risk Score is an analytical
indicator, not objective truth** — it encodes real methodological
choices (which components to include, how much to weight each, and the
still-provisional normalization thresholds from `docs/risk_score_design.md`)
that a different, equally reasonable analyst could have made
differently and arrived at a different number. Two further sources of
uncertainty compound whatever this sensitivity analysis shows, and
neither is addressed by it:

- **Normalization thresholds remain provisional** (`docs/risk_score_design.md`,
  `R/05_risk_score.R`) — arbitrary reference ranges, not calibrated
  against real domain benchmarks or accumulated snapshot history. This
  analysis only tests weight sensitivity, holding those thresholds fixed;
  it does not test sensitivity to the normalization choice itself.
- **Interconnection queue MW is not deliverable MW.** Every component in
  this score reflects potential capacity currently in the queue, never
  guaranteed future generation — this framing must travel with the score
  wherever it's presented, independent of which weighting scenario
  produced it.

Any presentation of this score — a chart, a sentence in a report, a
dashboard tile — should carry this framing explicitly, per `CLAUDE.md`'s
existing guardrail: present the weighting scheme and sensitivity results
alongside the score, never as a bare ranking.

## Conclusion

The Queue Attrition Rate of 32% (253,000 MW withdrawn ÷ 791,939 MW total
queue) is a cumulative figure, not a snapshot of current conditions —
it reflects everything that has ever entered the Berkeley Lab ERCOT
interconnection queue between 1995 and 2026, not the status of any
single cohort of projects at one point in time. Even accounting for
that, a rate this high still signals meaningful risk: nearly a third of
all capacity that has ever sought interconnection in ERCOT has
ultimately been withdrawn, suggesting a substantial share of today's
active queue could face the same outcome.
