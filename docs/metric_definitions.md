# Metric Definitions

Data dictionary for `data/processed/analysis_metrics.csv`, produced by
`R/04_metrics.R` from `data/processed/integrated_analysis.csv`. Every
metric is one row in that CSV: `geography, time_period, as_of_date,
metric_name, value, unit, formula, is_valid, note`.

Compiled 2026-08-20. **Unexecuted as of this writing** — R packages
aren't installed in the environment this was written in, so nothing
below has been empirically confirmed by an actual run. The validation
table at the bottom is a hand-calculated, executable self-check built
into `R/04_metrics.R` (`validate_metric_formulas()`), designed so the
script fails loudly on first run if any formula doesn't match these
hand-computed expectations, rather than requiring a separate manual
verification step.

---

## 1–4. Corporate Demand MW / Total Queue MW / Active Queue MW / Withdrawn Queue MW

**Formula:** direct pass-through of the corresponding column in
`data/processed/integrated_analysis.csv`. No computation.

**Meaning:**
- **Corporate Demand MW** — ERCOT Large Load's `data_center` sector
  figure (`summary.by_sector` in `load_queue_summary.json`), as of the
  snapshot's `as_of_date`. Per `docs/decisions.md` (2026-08-19), chosen
  over `industrial` because it captures the actual scale of corporate
  demand (90.2% of the queue vs. 1.0%).
- **Total Queue MW** — `sum(mw_1)` across every Berkeley Lab ERCOT-region
  project with a `q_date` on or before `as_of_date` (the
  "cumulative-entered" definition, `docs/decisions.md`, 2026-08-19),
  regardless of current `q_status`.
- **Active Queue MW** — the same sum, restricted to `q_status == 'active'`.
- **Withdrawn Queue MW** — the same sum, restricted to
  `q_status == 'withdrawn'`.

**Division-by-zero:** not applicable — these are sums/lookups, not
ratios.

**Missing-value handling:** if the source column in
`integrated_analysis.csv` is `NA`, the metric is `NA` with
`note = "Missing in the integrated dataset input — not silently treated
as zero."` `is_valid = FALSE` in that case.

---

## 5. Queue Attrition Rate

**Formula:** `withdrawn_queue_mw / total_queue_mw`

**Meaning:** the fraction of everything that ever cumulatively entered
the Berkeley Lab ERCOT queue (by `as_of_date`) that has since been
withdrawn.

**Important caveat — this is a simple cumulative ratio, not a cohort
attrition rate.** A conventional "attrition rate" in a survival-analysis
sense would measure what fraction of projects entering in a given period
are later withdrawn *within some time window*. The underlying data
doesn't support that here — it doesn't track how long a project sat in
the queue before withdrawing, only whether it currently has
`q_status == 'withdrawn'`. Read this metric as "share of the cumulative
queue no longer active due to withdrawal," not as a time-normalized
churn rate.

**Division-by-zero:** if `total_queue_mw == 0`, the metric is `NA` with
`note = "total_queue_mw is zero — attrition rate undefined (would
require dividing by zero)."` Not expected against real data (the current
snapshot has `total_queue_mw` in the tens of thousands of MW), but
handled explicitly regardless.

**Missing-value handling:** if either `withdrawn_queue_mw` or
`total_queue_mw` is `NA`, the metric is `NA` with an explicit note — the
result is never silently computed as if the missing value were zero.

---

## 6. Demand Pressure Ratio

**Formula:** `corporate_demand_mw / total_queue_mw`

**Meaning:** how many multiples of everything ever cumulatively entered
the Berkeley Lab ERCOT supply pipeline would be needed to satisfy
current corporate demand. A value above 1 means demand exceeds total
queue capacity; below 1 means total queue capacity exceeds demand.

**Why `total_queue_mw`, not `active_queue_mw`:** changed 2026-08-26
(`docs/decisions.md`), superseding the original 2026-08-20 decision to
use `active_queue_mw`. `docs/analytical_critique.md`'s robustness check
found the active-vs-total choice alone swings this ratio from ~1.03 to
~0.53 — a bigger lever on the headline finding than the entire
weighting sensitivity analysis (`R/06_sensitivity_analysis.R`) produced.
Samantha chose `total_queue_mw` as the more transparent, less
assumption-laden base. **`active_queue_mw` is still computed and
reported as its own metric (#3 above)** — it's just no longer the
denominator here.

**Division-by-zero:** if `total_queue_mw == 0`, the metric is `NA` with
`note = "total_queue_mw is zero — demand pressure ratio undefined
(would require dividing by zero)."`

**Missing-value handling:** if either `corporate_demand_mw` or
`total_queue_mw` is `NA`, the metric is `NA` with an explicit note.

---

## 7. Delivery Gap MW

**Formula:** `corporate_demand_mw - total_queue_mw`

**Meaning:** the MW gap between current corporate demand and everything
ever cumulatively entered the queue. Positive = demand exceeds total
queue capacity (a shortfall); negative = total queue capacity currently
exceeds demand (not an error — a meaningful result in its own right).

**This is the headline metric of the whole project** — the direct,
quantified answer to the research question ("where is corporate
electricity demand outpacing the grid's interconnection capacity to
deliver it, and by how much?" — renamed 2026-08-26, see
`docs/decisions.md`). Because of that, its framing matters more than any
other metric in this file.

**HARD GUARDRAIL, repeated here deliberately (see `CLAUDE.md`):**
interconnection queue MW is **not** deliverable MW. "Delivery Gap MW" is
a gap between corporate demand and **potential future generation
capacity currently progressing through the interconnection queue** —
never a gap against actual, guaranteed, or already-delivered generation.
`total_queue_mw` describes queue *status* (everything ever entered,
including withdrawn/suspended/operational projects), not a promise that
any of it will ultimately reach or remain in commercial operation. Any
narrative sentence, chart title, or dashboard label built from this
metric must preserve that distinction — never phrase it as "the grid
can/can't deliver X MW," only as "X MW of demand exceeds/is covered by
potential capacity that has ever entered the ERCOT interconnection
queue."

**Division-by-zero:** not applicable — subtraction, not division.

**Missing-value handling:** if either `corporate_demand_mw` or
`total_queue_mw` is `NA`, the metric is `NA` with an explicit note —
never silently computed by treating the missing value as zero (which
would be a materially misleading number for the project's headline
metric).

---

## Validation table

Six hand-built example scenarios, run through the exact same
`compute_metrics()` implementation used on real data
(`R/04_metrics.R`'s `validate_metric_formulas()`). If any "Actual"
column doesn't match "Expected" when the script runs, it stops with an
error rather than silently writing a wrong number.

| # | Scenario | Metric | Inputs | Expected | Why |
|---|---|---|---|---:|---|
| 1 | Normal case | Corporate Demand MW | demand=400,000 | 400,000 | Pass-through |
| 1 | Normal case | Total Queue MW | total=200,000 | 200,000 | Pass-through |
| 1 | Normal case | Active Queue MW | active=100,000 | 100,000 | Pass-through |
| 1 | Normal case | Withdrawn Queue MW | withdrawn=50,000 | 50,000 | Pass-through |
| 1 | Normal case | Queue Attrition Rate | 50,000 / 200,000 | 0.25 | Straightforward division |
| 1 | Normal case | Demand Pressure Ratio | 400,000 / 200,000 | 2.0 | Straightforward division |
| 1 | Normal case | Delivery Gap MW | 400,000 − 200,000 | 200,000 | Straightforward subtraction |
| 2 | `total_queue_mw = 0` | Queue Attrition Rate | withdrawn=0, total=0 | `NA` | Division by zero, caught explicitly |
| 2 | `total_queue_mw = 0` | Demand Pressure Ratio | demand=400,000, total=0 | `NA` | Division by zero, caught explicitly — total_queue_mw is now the denominator too |
| 2 | `total_queue_mw = 0` | Delivery Gap MW | 400,000 − 0 | 400,000 | Subtraction still computes — div-by-zero only affects the ratio metric |
| 3 | `active_queue_mw = 0`, total normal | Demand Pressure Ratio | demand=400,000, total=200,000 | 2.0 | Confirms this metric no longer depends on `active_queue_mw` at all |
| 3 | `active_queue_mw = 0`, total normal | Delivery Gap MW | 400,000 − 200,000 | 200,000 | Same confirmation for Delivery Gap |
| 4 | `corporate_demand_mw` missing | Demand Pressure Ratio | demand=`NA`, total=200,000 | `NA` | Missing input, caught explicitly |
| 4 | `corporate_demand_mw` missing | Delivery Gap MW | `NA` − 200,000 | `NA` | Missing input, caught explicitly |
| 4 | `corporate_demand_mw` missing | Queue Attrition Rate | withdrawn=50,000, total=200,000 | 0.25 | Unaffected — doesn't depend on `corporate_demand_mw` |
| 5 | Clean round-number check | Queue Attrition Rate | withdrawn=25,000, total=100,000 | 0.25 | Independent re-check with different numbers |
| 6 | Total queue capacity exceeds demand | Delivery Gap MW | 50,000 − 200,000 | −150,000 | Negative result is meaningful, not an error |

**Changed 2026-08-26:** examples 1, 3, and 6 (and the newly-added checks
in example 2) reflect the switch from `active_queue_mw` to
`total_queue_mw` as the base for Demand Pressure Ratio and Delivery Gap
MW. Example 3 in particular was redesigned specifically to demonstrate
the new independence from `active_queue_mw` — its expected values are
now identical to what they'd be with `active_queue_mw` at any value,
since it's no longer read by either formula.
