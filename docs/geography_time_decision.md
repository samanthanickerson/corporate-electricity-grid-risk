# Geography & Time Unit Decision: Berkeley Lab "Queued Up" vs. ERCOT Large Load Queue

## 1. Scope & Method

### 1.1 What this document does
- Evaluates candidate common geographic/temporal units for comparing
  Berkeley Lab (supply-side) and the ERCOT Large Load interconnection
  queue via ercotqueue.com (demand-side) — the project's current core
  pairing, per `docs/decisions.md` (2026-08-17)
- Does **not** choose a final option — ends with a recommendation and
  explicit tradeoffs for Samantha to decide

### 1.2 Note on this document's history
- This replaces an earlier version of this file that compared Berkeley
  Lab against CEBA Deal Tracker. CEBA was fully removed from the project;
  this version covers the pairing actually in use now.
- **The picture here is meaningfully different from the CEBA version,**
  in one important way: geography is no longer a dead end. CEBA had zero
  geographic granularity at any grain. ERCOT Large Load data is
  ERCOT-scoped by construction, so a real, assumption-free geographic
  alignment exists this time. The gap that remains is granularity
  (aggregate vs. project-level) and time (single snapshot vs. historical
  series) — see 1.4.

### 1.3 The fields actually available
- **Berkeley Lab** (`03. Complete Queue Data`, 38,201 rows; 3,757 at
  `region=='ERCOT'`) — geographic: `state`, `region`, `county`,
  `fips_code`, `poi_name`. Temporal: `q_date`, `prop_date`, `on_date`,
  `wd_date`, `ia_date` (real per-project dates, 1995–2025), plus derived
  `q_year`, `prop_year`.
- **ERCOT Large Load queue** (`ercotqueue.com`, re-verified by direct
  fetch before writing this document — see 1.4): geographic fields exist
  in the schema (`county`, `load_zone`, `tsp`, `poi`) but are **null in
  all 8 currently published records**. Temporal: `load_queue_summary.json`
  carries one `as_of_date` (2026-06-18) for the whole summary;
  `load_projects.json`'s `submitted_date`/`in_service_date` are null in
  every record, leaving only `last_seen_date`/`last_changed_date`
  (ercotqueue.com's own tracking dates — roughly monthly: 2026-01-21,
  2026-02-13, 2026-04-01 — not the underlying project's real dates). A
  populated `sector` field (`data_center`, `crypto`, `industrial`,
  `mixed`) exists — a categorical, not geographic, dimension, parallel to
  Berkeley Lab's `type_1`/`type_clean`.

### 1.4 The structural fact that shapes every option below
**ERCOT Large Load's geography and dates are null by design, not by
missing collection.** The source's own `confidentiality_note` states:
*"Public aggregate only. ERCOT does not disclose a complete named
customer queue in this source."* This was re-confirmed with a fresh fetch
immediately before writing this document (all 8 records checked
individually) rather than assumed from memory. Two consequences:
- **Geography still aligns at the ERCOT-region level** — unlike CEBA, no
  allocation assumption is needed to say "this dataset represents ERCOT."
- **Sub-ERCOT geography (county, load zone) and true per-project dates
  are structurally unavailable from this public source** — this is a
  standing limitation, not something more data collection would fix.

---

## 2. Options Evaluated

### 2.1 Option 1 — County-level analysis
- **Data availability:** Berkeley Lab — yes (`county`, with the caveats
  already logged in `docs/data_reconnaissance.md`). ERCOT Large Load —
  the `county` field exists in the schema but is **null in every current
  record**.
- **Joinability:** Not joinable — there is no populated county value on
  the ERCOT Large Load side to join on, and per 1.4 this is a
  confidentiality-driven design choice, not a gap likely to close.
- **Interpretability:** N/A — nothing to interpret without real values.
- **Risk of misclassification:** Low risk of *producing* a wrong number,
  since there's nothing to compute — but high risk of a reader assuming
  county-level ERCOT Large Load data exists somewhere just because the
  field name is present in the schema.
- **Relevance to research question:** Would be the most granular option
  if it existed — it doesn't.
- **Potential loss of information:** Total loss on the ERCOT Large Load
  side; Berkeley Lab retains full county granularity if used alone.

### 2.2 Option 2 — ERCOT-region-level analysis
- **Data availability:** Berkeley Lab — yes, filter to `region=='ERCOT'`
  (3,757 rows). ERCOT Large Load — yes, **trivially**: the entire source
  is already ERCOT-scoped by construction (drawn from ERCOT's own LLWG
  reports), no filtering needed.
- **Joinability:** **Genuinely alignable, with no allocation assumption.**
  This is the key difference from the CEBA version of this analysis: both
  sides can honestly claim to represent "the ERCOT region" without
  estimating anything.
- **Interpretability:** High, with one caveat to state clearly: this is
  still an aggregate-vs-project-level alignment. Berkeley Lab is
  3,757 individual rows; ERCOT Large Load is 8 pre-aggregated bucket
  totals. "Alignable" means the two sides describe the same
  geography, not that they can be merged row-by-row into one table.
- **Risk of misclassification:** Low for the geography claim itself.
  Moderate if presented without the aggregate-vs-project-level caveat —
  a reader could assume a 1:1 join happened when it's really two
  independently-aggregated totals being placed side by side.
- **Relevance to research question:** High — this is the natural shared
  scope of both core datasets as currently defined.
- **Potential loss of information:** No sub-ERCOT breakdown (can't
  compare by load zone or county) since ERCOT Large Load has nothing
  populated below the ERCOT-wide level.

### 2.3 Option 3 — County + Year
- **Data availability:** Compounds Option 1's problem with a temporal
  one. Berkeley Lab has a real annual series (`q_year`, spanning
  1995–2025). ERCOT Large Load has one current snapshot (`as_of_date`
  2026-06-18) plus a handful of ercotqueue.com's own monthly tracking
  dates — not a multi-year series comparable to Berkeley Lab's.
- **Joinability:** Not joinable — inherits Option 1's total absence of
  county data, plus there's no ERCOT Large Load year-over-year series to
  align against Berkeley Lab's `q_year`.
- **Interpretability:** N/A for the same reason as Option 1.
- **Risk of misclassification:** N/A — nothing to compute.
- **Relevance to research question:** Would be the richest option (place
  and time together) if the underlying data existed — it doesn't, on
  either the geographic or temporal axis for ERCOT Large Load.
- **Potential loss of information:** Total, compounding Option 1.

### 2.4 Option 4 — ERCOT-region + Snapshot
- **Data availability:** Region — yes, both sides (as in Option 2). Time
  — Berkeley Lab can be sliced to match any date (e.g. `q_date <=
  2026-06-18`, to align with ERCOT Large Load's `as_of_date`); ERCOT
  Large Load only offers that one current snapshot per fetch — repeated
  fetches over time would be needed to build a real series on that side.
- **Joinability:** Real geographic alignment (as in Option 2), but
  temporal alignment is **asymmetric**: Berkeley Lab has decades of
  history to choose a comparison point from; ERCOT Large Load has
  exactly one "as of" date available right now. The honest framing is
  "Berkeley Lab's ERCOT-filtered state as of [date] vs. ERCOT Large
  Load's current totals" — a **snapshot comparison**, not a joined trend.
- **Interpretability:** Good if explicitly framed as a snapshot; risky if
  presented in a way that implies a time series exists on both sides.
- **Risk of misclassification:** Moderate — the biggest risk in this
  whole document is implying demand-side growth trends that the data
  doesn't actually support yet.
- **Relevance to research question:** High — matches a "where does
  demand stand against the queue right now" framing well.
- **Potential loss of information:** No demand-side historical trend
  (only supply-side/Berkeley Lab has one) until ERCOT Large Load is
  fetched repeatedly over time to build a series.

### 2.5 Option 5 — Other defensible common unit: ERCOT-region totals presented as parallel summary statistics, not row-joined
- **What this means concretely:** Report Berkeley Lab's `region=='ERCOT'`
  totals (by status, by resource type, for a chosen date range) and
  ERCOT Large Load's own aggregate totals (by status funnel, by sector)
  side by side — e.g. "Berkeley Lab: X MW of generation capacity in the
  ERCOT interconnection queue as of [date]" next to "ERCOT Large Load:
  Y MW of large-load demand submitted as of 2026-06-18" — without
  claiming a row-level merge.
- **Data availability:** Full, for both sides, at this grain.
- **Joinability:** Deliberately not a row-level join — this is the
  honest response to the aggregate-vs-project-level grain mismatch (a
  different reason than CEBA's version of Option 5, which existed
  because CEBA had no geography at all).
- **Interpretability:** Highest of the options involving both sources —
  no false precision implied.
- **Risk of misclassification:** Lowest, provided the snapshot-vs-series
  caveat from Option 4 is stated alongside it.
- **Relevance to research question:** Directly usable for the project's
  "where is demand outpacing grid readiness" framing, at the level of
  precision the data actually supports.
- **Potential loss of information:** No project-level detail on the
  demand side (can't drill into individual large-load requests — ERCOT
  doesn't publish them), and no true multi-year demand trend yet.

---

## 3. Summary Comparison

| Option | Geography aligns? | Real join possible? | Misclassification risk | Info lost |
|---|---|---|---|---|
| 1. County | No (ERCOT Large Load: null) | No | Low (nothing to compute) | Total (ERCOT Large Load side) |
| 2. ERCOT region | **Yes** | Alignable, not row-joinable (grain mismatch) | Low–Moderate | Sub-ERCOT breakdown |
| 3. County + Year | No | No | Low (nothing to compute) | Total, compounded |
| 4. ERCOT region + Snapshot | **Yes** | Alignable as a snapshot, not a series | Moderate (trend-implication risk) | Demand-side historical trend |
| 5. ERCOT-region totals, parallel, not joined | **Yes** | N/A by design | Lowest | Project-level demand detail |

---

## 4. Recommendation — DECIDED 2026-08-19

**Samantha has decided:** Options 2/4/5 combined — `region=='ERCOT'` as
the shared geographic unit (a real alignment, not an assumption), with
any comparison treated as a **snapshot alignment of two independently-
aggregated totals**, not a row-level join or a demand-side trend.
Concretely: Berkeley Lab's ERCOT-filtered totals, sliced to the most
recent date that aligns with ERCOT Large Load's current `as_of_date`,
reported next to ERCOT Large Load's current aggregate totals — with both
caveats (aggregate vs. project-level; snapshot vs. series) stated
wherever the comparison appears.

**The full decision record, including why this pairing was chosen over
the alternatives and the practical implications for future pipeline
work, is in `docs/decisions.md`** (2026-08-19 entry, "Composite dataset
units"). What follows below is the supporting tradeoff analysis this
decision was based on.

- Geography is no longer the blocker it was with CEBA — `region=='ERCOT'`
  genuinely applies to both sources. The remaining limitation is grain:
  Berkeley Lab is project-level, ERCOT Large Load is aggregate-only by
  ERCOT's own confidentiality policy. No amount of better data sourcing
  changes that on the ERCOT Large Load side — it's a standing feature of
  what ERCOT publicly discloses.
- A single-snapshot demand comparison is honest but limited — it can say
  "here's where things stand" but not "here's the demand trend over
  time," unlike the supply side. Building a real demand-side series would
  require re-fetching ercotqueue.com repeatedly and storing each
  snapshot — worth considering if trend analysis becomes a priority.
- **What would change this recommendation:** if ERCOT ever discloses
  project-level Large Load data (unlikely given the stated
  confidentiality policy) or if ercotqueue.com adds finer geography,
  Option 1/3 (county-level, with or without year) would become
  evaluable. Until then, the ERCOT-region snapshot alignment is the
  finest defensible unit available.
