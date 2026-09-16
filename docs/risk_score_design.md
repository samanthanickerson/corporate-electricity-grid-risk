# Procurement Risk Score — Design Memo

Methodological evaluation of four candidate score components, to help
decide how the Procurement Risk Score should work. **No score has been
built** — per `CLAUDE.md`'s existing guardrail ("the Procurement Risk
Score is an analytical construct, not objective truth... always present
it with its weighting scheme and sensitivity results alongside it, never
as a bare ranking"), this memo is the groundwork that guardrail assumes
exists before the score itself gets built.

Compiled 2026-08-20, grounded entirely in already-verified project facts
(`docs/decisions.md`, `docs/metric_definitions.md`,
`docs/data_dictionary.md`, `docs/data_reconnaissance.md`,
`docs/cleaning_code_review.md`) — nothing here required running R.

---

## The foundational question this memo has to answer first

Before evaluating any component against the six requested criteria,
there's a prior question those criteria can't be answered without:
**what is this score actually scoring — one thing, or many things being
compared to each other?**

Two of the four candidate components — Demand Pressure and Delivery
Gap — are already computed as **single region-wide aggregate figures**:
one number for all of ERCOT, for one snapshot
(`docs/decisions.md`, 2026-08-19: "two independently-aggregated,
ERCOT-wide totals... not a row-level join"). Queue Attrition is the
same. Queue Age is the one component that could *either* stay
region-wide (e.g., median age of currently-active queue capacity) *or*
become genuinely project-level (each of the 3,608 in-scope Berkeley Lab
projects gets its own age). If the score mixed region-wide and
project-level components, most rows would just repeat the same regional
constant for three of four components — not a real per-project score,
just one number copy-pasted next to genuine per-project variation in the
fourth.

**Recommendation: keep the score entirely region-level** — all four
components as ERCOT-wide aggregates for the current snapshot, producing
one composite score, **trackable across successive pipeline runs over
time** (a monitoring indicator), not a cross-sectional ranking tool.
This is the only framing consistent with the project's existing
aggregate-vs-project grain mismatch (no shared key between Berkeley Lab
and ERCOT Large Load, per `docs/decisions.md`) without inventing a new
join the data doesn't support. A genuine project-level risk score is a
substantially larger, separate undertaking — it would need Demand
Pressure and Delivery Gap redefined entirely, since regional demand
doesn't decompose to individual projects. Worth flagging as a real
future direction, not recommended for this round.

**The rest of this memo evaluates the four components under that
region-level framing** — this is Samantha's call to confirm or override,
since it changes what "conceptually relevant" and "available in the
data" mean for each component below.

---

## 1. Demand Pressure

*Existing `Demand Pressure Ratio` = `corporate_demand_mw / active_queue_mw` (`R/04_metrics.R`)*

| Criterion | Assessment |
|---|---|
| Conceptually relevant | Yes — directly measures how much pressure current demand places on the currently-viable supply pipeline, core to the project's research question. |
| Statistically appropriate | It's a ratio: unbounded above, floored at 0, right-skewed. Not on a comparable scale to a bounded proportion (Attrition) or a raw MW quantity (Gap) without transformation. |
| Available in the data | Yes, already computed. |
| Redundant with another component | **Yes — significantly, with Delivery Gap.** See "Key finding" below. |
| Vulnerable to outliers | Today this is one snapshot value, so "outlier" doesn't apply in the usual multi-observation sense. If tracked across future snapshots, it would be — ratios are sensitive to denominator fluctuations; if `active_queue_mw` ever shrinks, small absolute changes produce large ratio swings. |
| Sensitive to missing data | Yes — already handled explicitly in `R/04_metrics.R` (`NA` if either input is missing, or if `active_queue_mw == 0`). The *composite score* still needs its own policy for what happens when one component is `NA` (exclude and re-normalize remaining weights, or make the whole score `NA`) — an open question, not resolved here. |

**Recommended normalization:** a log-ratio transform
(`log(corporate_demand_mw / active_queue_mw)`) is the statistically
appropriate shape for a right-skewed, non-negative ratio — but see "The
normalization problem" section below before treating this as usable
today.

---

## 2. Queue Attrition

*Existing `Queue Attrition Rate` = `withdrawn_queue_mw / total_queue_mw` (`R/04_metrics.R`)*

| Criterion | Assessment |
|---|---|
| Conceptually relevant | Yes, but **directionally ambiguous** — needs Samantha's judgment, not just data. High attrition could mean genuine project failure (a real risk signal) *or* healthy queue "churn," where speculative/low-quality interconnection requests get filtered out over time — some grid-policy literature treats attrition as a *positive* signal (less phantom congestion from projects that were never going to be built). The sign this component gets in the composite score depends entirely on which reading is intended. |
| Statistically appropriate | Yes — a proportion naturally bounded [0, 1], the best-behaved of the four for direct combination without transformation. |
| Available in the data | Yes, already computed. |
| Redundant with another component | **Partially, with Queue Age.** Both are downstream of the same "project vintage/maturity" pathway — older cohorts have had more time to resolve one way or another, so a pooled cumulative attrition rate across 30 years of `q_date` vintages is partly just a proxy for "how mature is this queue, on average." Not the near-total overlap Demand Pressure/Delivery Gap have, but a real correlation worth checking empirically once both are computed, not assumed independent. |
| Vulnerable to outliers | Yes, via **vintage-mixing**, not simple value outliers — "cumulative-entered" pools 1995–2025 vintages into one ratio, so an old, mostly-resolved cohort from decades ago can dominate the numerator without representing *current* queue health. A single very large withdrawn project could also swing the ratio disproportionately. |
| Sensitive to missing data | Low, for this specific formula. The already-documented gap (594 ERCOT withdrawn rows, 51.3%, missing `wd_date`) does **not** affect this calculation — it's based on `q_status == 'withdrawn'`, not `wd_date`. Worth stating explicitly since it's a genuine non-issue here, unlike it would be for any future cohort/time-based attrition measure (already flagged as out of scope in `docs/metric_definitions.md`). |

**Recommended normalization:** no shape transform needed (already
[0, 1]) — but still needs the same reference-distribution treatment as
the ratio-type components before it's meaningfully "high" or "low" in a
score.

---

## 3. Queue Age

*Not yet computed anywhere in this project — new for the score.*

| Criterion | Assessment |
|---|---|
| Conceptually relevant | Yes — a standard, intuitive risk signal: active projects that have sat in the queue a long time without resolving (to operational or withdrawn) often indicate interconnection bottlenecks, financing difficulty, or a stalled project. |
| Statistically appropriate | Depends entirely on the aggregation choice. A simple mean age is **not** appropriate given Berkeley Lab's 30-year `q_date` span; a median or MW-weighted median is. |
| Available in the data | Yes — `q_date` is already cleaned and timezone-corrected (`docs/cleaning_code_review.md`, Finding 1.1, fixed 2026-08-20). Age = `as_of_date - q_date` for any active, in-scope project. Not yet computed anywhere, but the underlying field is fully available and already trustworthy. |
| Redundant with another component | Partially with Queue Attrition (shared vintage/maturity pathway, above) — but **largely independent of Demand Pressure and Delivery Gap**, which are driven by *current* demand and *current* active-capacity totals, not by the age distribution of the projects making up that capacity. This is a point in favor of including it — one of the few components likely to add genuinely new information rather than restating what another component already captures. |
| Vulnerable to outliers | **Yes, significantly, if aggregated as a simple mean.** A handful of unusually old still-"active" projects (`docs/data_reconnaissance.md` already documents genuine status/date oddities — e.g., 158 file-wide "active" rows with a populated `on_date`, suggesting some status-transition noise) could badly skew a mean upward. |
| Sensitive to missing data | The already-documented 149 ERCOT rows (4.0%) missing `q_date` are already excluded from the "in-scope" cumulative-entered set by `R/03_data_integration.R`, so Queue Age inherits that exclusion for free — no new missing-data problem introduced. Worth verifying once computed, not assumed: whether that 4.0% is evenly spread across `q_status` values or concentrated in one (e.g., if missing-`q_date` rows are disproportionately `active`, the age calculation's effective sample shrinks more than the headline 4.0% suggests). |

**Recommended normalization:** **MW-weighted median** age in days or
years — robust to a handful of extreme-age projects, and consistent with
the MW-centric framing already used by every other metric in this
project. Age has no natural [0, 1] bound, so it needs the same
reference-distribution treatment as the ratio-type components (see
below) before it's meaningfully "high" or "low."

---

## 4. Delivery Gap

*Existing `Delivery Gap MW` = `corporate_demand_mw - active_queue_mw` (`R/04_metrics.R`)*

| Criterion | Assessment |
|---|---|
| Conceptually relevant | Yes — arguably the *most* directly relevant to "procurement risk" specifically; a raw MW shortfall is intuitive and matches the project's headline research-question framing exactly. **Hard guardrail carried over from `docs/metric_definitions.md`:** this must always be framed as a gap against *potential* capacity currently in the queue, never against guaranteed deliverable capacity — that framing has to travel into the score's documentation too, not just the metrics file. |
| Statistically appropriate | Unbounded, can be positive *or* negative (unlike the other three, which are all non-negative). This asymmetry needs explicit handling in any normalization scheme — can't log-transform directly, since negative values are valid and meaningful, not errors. |
| Available in the data | Yes, already computed. |
| Redundant with another component | **Yes — the same finding as Demand Pressure**, since they share identical inputs. See "Key finding" below. |
| Vulnerable to outliers | Same as Demand Pressure — single snapshot today; sensitive to single-point anomalies if tracked over time. |
| Sensitive to missing data | Same as Demand Pressure — `NA` if either input is missing, already handled explicitly and documented in `R/04_metrics.R`/`docs/metric_definitions.md`. |

**Recommended normalization:** a sign-aware scaling (e.g., separate
treatment of the positive "shortfall" region and negative "surplus"
region, or a bounded transform like `tanh`) rather than a log transform —
specifically because zero and negative values are meaningful here, not
edge cases to exclude.

---

## Key finding: Demand Pressure and Delivery Gap are not two components

**They're one relationship (`corporate_demand_mw` vs. `active_queue_mw`)
expressed two ways** — a ratio and a difference of the identical pair of
inputs. They are two mathematical transformations of the same
underlying signal, not two independent pieces of information. Including
both in a composite score effectively double-weights "demand vs. active
supply" relative to Queue Attrition and Queue Age, which draw on
genuinely different inputs. This is the single most consequential
finding in this memo.

**Recommend picking one of:**
- **Keep only one.** Delivery Gap for direct MW interpretability;
  Demand Pressure Ratio if a bounded, cross-snapshot-comparable ratio is
  preferred. The simplest, most defensible fix.
- **Keep both, but as a single effective weight.** If both are wanted
  for different audiences (a ratio for analysts, a raw MW gap for
  executives), the score's weighting scheme should treat them as one
  combined vote, not two independent ones — otherwise the "demand vs.
  active supply" relationship silently gets double the influence of
  Queue Attrition or Queue Age in the final score.

Queue Attrition and Queue Age have a real but partial correlation
(shared vintage/maturity pathway, noted in both sections above) — worth
checking empirically once both are computed, but not the same
near-exact duplication as the first pair.

---

## The normalization problem this memo has to be honest about

**None of these four components can be properly normalized (z-score,
min-max, percentile rank) yet, because normalization requires a
reference distribution, and today there is exactly one observation** —
ERCOT, one snapshot (per the 2026-08-20 decision that the integrated
dataset is a single row, not a time series). The per-component
recommendations above describe the right *transform shape* for each
component's distribution (log-ratio, proportion, weighted-median-age,
sign-aware scaling) — but what to scale each transformed value *against*
has two real options, and this is squarely Samantha's call:

- **Domain-anchored reference points** — e.g., "a Demand Pressure Ratio
  above 3.0 is high risk, below 0.5 is low risk," based on outside
  energy-industry knowledge, not derivable from this project's data
  alone.
- **Wait for accumulated history** — once the pipeline has run across
  several snapshots (e.g., monthly for 6–12 months), a genuine empirical
  distribution would exist to normalize against, and the score would
  become meaningfully trackable over time, matching the region-level
  framing recommended above.

---

## Open questions for Samantha to decide (not resolved in this memo)

1. **Region-level vs. project-level scope** — confirm or override the
   region-level recommendation above.
2. **Keep one or both of Demand Pressure / Delivery Gap** — and if both,
   how their combined weight is handled.
3. **Queue Attrition's directionality** — is higher attrition a risk
   signal or a healthy-churn signal, for this project's purposes?
4. **Normalization reference points** — domain-anchored thresholds, or
   wait for accumulated snapshot history?
5. **Missing-component policy** — if one component is `NA` for a given
   snapshot, does the whole score become `NA`, or do remaining weights
   get re-normalized?

## Out of scope for this memo

Not building the score. Not computing Queue Age in code yet — that's a
future `R/` script decision, once the aggregation approach above is
confirmed. Not resolving questions 3–5 above; they're Samantha's
decisions, consistent with `CLAUDE.md`'s role split ("Defining the
research question and methodology" is her domain).
