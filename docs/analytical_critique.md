# Analytical Critique

A deliberately skeptical, senior-analyst review of this project against
its own research question, as it stood at the time of this review:
**"Where is corporate clean energy demand outpacing the grid's ability
to deliver it, and by how much?"** (§0 below prompted a same-day rename
— see `docs/decisions.md`, 2026-08-26 — to "Corporate Electricity Demand
vs. Grid Interconnection Capacity"; the finding is kept in its original
wording since it's what motivated that change.)

Reviewed 2026-08-26. **No code or data was modified in this pass** —
review only, per explicit instruction. Grounded in `docs/decisions.md`,
`docs/risk_score_design.md`, `docs/metric_definitions.md`,
`docs/cleaning_code_review.md`, `docs/geography_time_decision.md`,
`R/01`–`R/07`, and the real executed output now in
`data/processed/procurement_risk_scores.csv` and
`data/processed/ercot_large_load_queue_summary.csv` (including that
file's own `source_citation` text, which grounds several findings below
that no prior document raised). Findings are not re-litigated where
`docs/cleaning_code_review.md` or `docs/risk_score_design.md` already
cover them in depth — those are cited and built on, not duplicated
verbatim.

Each finding is tagged with which of the seven requested categories it
falls under: **[FLAW]** methodological flaw, **[MISLEAD]** possible
misleading interpretation, **[REDUNDANT]** redundant variable,
**[CONFOUND]** confounding factor, **[CAUSATION]** correlation-vs-
causation risk, **[UNSUPPORTED]** a claim the data cannot support,
**[ROBUSTNESS]** an additional check worth running.

---

## 0. The finding that cuts across everything below

**[RESOLVED 2026-08-26 — see `docs/decisions.md`, 2026-08-26.]** The
finding below led directly to a same-day decision: rather than adding
generation-technology filtering to match the old "clean energy" name
(which would only have been possible on the supply side, not the
demand side — see that decision's "Alternatives considered"), the
project's name and research question were changed to
**"Corporate Electricity Demand vs. Grid Interconnection Capacity"** in
`CLAUDE.md`/`README.md`, matching what the pipeline actually measures.
The original finding is preserved below, unedited, since it's what
prompted the fix and remains an accurate description of *why* the old
name was a problem.

**[FLAW] [UNSUPPORTED]** The project's title and research question are
about *corporate clean energy demand*. Nothing in the pipeline actually
measures "clean energy" anything. `corporate_demand_mw` is ERCOT Large
Load's `data_center` sector — a queue of large-load *electricity*
interconnection requests, with zero information about whether that load
wants renewable, nuclear, gas, or any generation mix at all. The supply
side is explicitly **not** filtered by generation technology either
(`docs/decisions.md`, 2026-08-19: "the grid pools all generation to
serve all load — there's no dataset-level correspondence between a
generation technology and a load sector to preserve by filtering both
sides"). That is a defensible technical decision on its own terms, but
its consequence is total: **the word "clean" in this project's own name
is not operationalized anywhere in the code.** Every number this
pipeline produces is really answering "where is corporate *electricity*
demand outpacing grid interconnection capacity" — a real and useful
question, but a different one than the one on the tin. This should be
either fixed (filter Berkeley Lab's `type_1`/`type_clean` to renewable
categories, which the data supports) or the project's stated scope
should be explicitly narrowed to match what's actually measured.

---

## 1. Dataset integration

**[MISLEAD]** The word "integration," and the filename
`integrated_analysis.csv`, both suggest more than what actually happens.
Per `docs/decisions.md` (2026-08-19), this is **two independently-
aggregated totals placed side by side**, never a row-level join — a
correct and well-documented design choice, but one whose name invites a
reader to assume a real merge occurred. A reader skimming just the
filename, without reading the methodology notes carried in every output
row, could easily over-trust the relationship between the two figures.

**[FLAW]** The two sources measure structurally different things sharing
only a unit, not an engineering meaning: Berkeley Lab counts *generation*
interconnection requests (supply-side, MW of generation capacity seeking
to connect); ERCOT Large Load counts *load* interconnection requests
(demand-side, MW of electricity draw seeking to connect). "MW" is the
same unit on both sides, but a generation-queue MW and a load-queue MW
are not interchangeable or netting quantities in any strict electrical
sense — see §6 (Delivery Gap) for why this matters for the headline
metric specifically.

**[FLAW]** ercotqueue.com is an **unverified third-party** re-publication
of ERCOT's own LLWG PPTX slides. The project's own data dictionary
already flags this as **[NEEDS VERIFICATION]** — it has never been
independently cross-checked against the original ERCOT filing. Every
demand-side number in this entire project inherits that unverified
provenance silently once it's sitting in a clean CSV.

**[MISLEAD]** The "reconciliation" report
(`output/analysis/integration_reconciliation.csv`) only verifies internal
arithmetic *within* Berkeley Lab (`in_scope + unmatched_missing_date +
unmatched_future_date == total`). It does not, and structurally cannot,
cross-validate Berkeley Lab against ERCOT Large Load — there is no
shared key or overlapping figure between the two sources to check
against each other. Calling this a "reconciliation" risks implying
cross-source validation happened. It didn't, and can't, given the data.

**What to verify:** whether "integration" is the right word to use in
any external-facing material (a dashboard, a write-up) without the
same caveat this file already carries internally.

---

## 2. Geographic alignment

**[FLAW]** `region=='ERCOT'` is a real, non-assumed geographic alignment
— genuinely the project's strongest methodological foundation, and it
deserves credit as such (`docs/geography_time_decision.md` documents
real alternatives that were rejected for good reason). That said:

- Berkeley Lab's own `region` classification is trusted without
  independent audit. No process in this pipeline spot-checks a sample of
  `region=='ERCOT'` rows against known project names or coordinates.
- ERCOT Large Load has **zero** sub-regional geography in every currently
  published record (`county`, `load_zone`, `tsp`, `poi` are all null by
  ERCOT's own confidentiality policy, per `docs/geography_time_decision.md`).
  "ERCOT" isn't a chosen grain for this source — it's the *only* grain
  available. That's worth stating plainly rather than presenting region-
  level alignment as an analytical choice on both sides equally.
- **854 ERCOT rows (22.7%) are missing `state`.** This was reasoned to be
  benign via a documentation review (`docs/data_reconnaissance.md`,
  2026-08-17) — never re-verified against the pipeline's actual executed
  output.
- ERCOT's balancing-authority footprint has itself changed over the
  30-year span Berkeley Lab's `q_date` covers (1995–2025). A project
  tagged `region=='ERCOT'` from 1995 may reflect a present-day
  retroactive classification, not what the grid operator considered its
  footprint at the time. This is a real, if subtle, historical-boundary
  confound baked into any pooled 30-year total.

**[ROBUSTNESS]** Spot-audit a sample of Berkeley Lab `region=='ERCOT'`
rows (e.g., by `county`/`poi_name`) against a known map of ERCOT's
current footprint, and separately re-verify the 854-row missing-`state`
count against the actual executed `queued_up_clean.csv` rather than
relying on a pre-execution finding.

---

## 3. Time alignment

The core asymmetry — Berkeley Lab's real 30-year history vs. ERCOT Large
Load's single `as_of_date` snapshot — is already extensively documented
(`docs/decisions.md`, 2026-08-19/20) and correctly never framed as a
demand-side trend. Two sharper points beyond what's already written down:

**[FLAW] [MISLEAD]** `corporate_demand_mw` is **not actually a clean
"point-in-time demand level"** the way the framing implies — it's itself
a cumulative gross total (see §4 below for the full mechanism). So the
comparison isn't really "one accumulated 30-year supply figure vs. one
instantaneous demand reading" — it's closer to "one accumulated supply
total vs. one accumulated demand total, from two sources with very
different accumulation windows and no shared start date." That's a
meaningfully different (and less clean) comparison than "history vs.
current state," and it isn't stated anywhere in the existing decision
record.

**[CONFOUND]** ercotqueue.com's own citations disclose a **slide-to-slide
discrepancy for the same figure** — 8,927 MW vs. 8,926 MW for
"approved-to-energize" capacity in the same snapshot (both values
preserved in the citation rather than silently picking one, which is
good practice by that source) — meaning the underlying primary source
itself has measurement noise at roughly the same order of magnitude as
a small month-to-month change this pipeline would otherwise report as a
real signal, once repeated snapshots exist.

**What to verify:** whether any future month-over-month change in
`corporate_demand_mw` smaller than roughly this noise floor (~1 MW in
~9,000, i.e. ~0.01%, though the noise floor for the much larger
`data_center` figure specifically is unknown and untested) should be
treated as a real change at all.

---

## 4. Demand definition

**[FLAW] [UNSUPPORTED]** — see §0. This is the project's central
definitional gap.

**[FLAW]** Re-checking the actual executed `ercot_large_load_queue_summary.csv`'s
own `source_citation` text surfaces a mechanism not previously documented
anywhere in this project: the `data_center` sector figure (420,812 MW)
is ERCOT's own **90.2% share of the full 466,497 MW gross Large Load
queue** — i.e., every large-load request currently on file for that
sector, regardless of status. The same source discloses that of the
full queue, **8,927 MW has already received "Approval to Energize,"** and
of that, **3,900 MW is already "observed operating"** (i.e., already
being served, already drawing power). Nothing in `R/01`–`R/03` filters
the `data_center` sector total to exclude this already-completed
segment. By contrast, the supply-side `active_queue_mw` **explicitly
excludes** `is_operational`/`is_withdrawn`/`is_suspended` projects — only
currently-in-progress capacity counts.

**Why this matters:** `corporate_demand_mw`, as used in every downstream
metric, is not "genuinely outstanding demand" — it includes some amount
of load that is already being served. The magnitude of this specific
effect looks modest today (3,900 MW of ~420,812 MW sector total, if the
sector mix of "observed operating" load matches the overall mix — an
assumption this pipeline has no way to verify, since the operating
breakdown isn't published by sector), but the *mechanism* is a real,
asymmetric filtering choice between the two sides of every headline
ratio in this project, not a rounding footnote.

**[FLAW]** Excluding "crypto" (14,928 MW, 3.2% of the queue) from
"corporate demand" is a defensible, documented scope choice
(`docs/decisions.md`, 2026-08-19) — but crypto-mining operations are
themselves corporate entities drawing large electricity loads, and their
exclusion is a definitional choice that shapes the headline number, not
a neutral default.

**What to verify:** whether ERCOT/ercotqueue.com ever publishes a
status-by-sector cross-tab that would let this pipeline filter
`corporate_demand_mw` to exclude already-energized load specifically,
closing the asymmetry with `active_queue_mw`.

---

## 5. Queue-capacity definition

Status reflects each project's **current** standing, never its
historical status at a past date — already well documented and correctly
caveated everywhere it's used (`R/07`'s chart captions, `docs/decisions.md`).
Two further points:

**[FLAW]** No filtering by generation technology (ties directly to §0/§4
— "clean" is unoperationalized on the supply side too).

**[FLAW] [UNSUPPORTED]** No locational/deliverability information at all.
MW "active" in the interconnection queue says nothing about whether that
capacity can physically reach the transmission nodes where large-load
demand is actually sited. ERCOT has a well-documented history of
transmission-constrained regions (e.g., West Texas wind generation
historically outpacing transmission buildout to load centers). An
aggregate region-wide MW balance is a genuinely weak proxy for "can the
grid deliver this" if the generation and the load are electrically
distant from each other — which this data cannot determine either way,
since neither source publishes sub-ERCOT location for the demand side.

---

## 6. Delivery gap

**[FLAW]** This is the project's headline metric, and it directly
inherits §4's filtering asymmetry: it nets a supply figure that
*excludes* already-built capacity against a demand figure that does
*not exclude* already-served load. It also subtracts two structurally
different queue types (§1) as though MW-for-MW fungible — a real
engineering oversimplification that the existing hard guardrail ("queue
MW is not deliverable MW") only partially covers. The guardrail warns
against over-claiming what the *supply* side means; it doesn't address
that the *subtraction itself* nets two non-equivalent quantities.

**[MISLEAD]** Reporting "+13,400 MW" to the nearest hundred implies a
level of precision the underlying inputs don't support, given: the
disclosed source-level noise (§3), the demand-side filtering asymmetry
(§4), and the fact that this is a difference of two very large,
independently-sourced numbers (a classic case where absolute-value
precision outstrips the precision of either input).

**What to verify:** present this figure with an explicit uncertainty
band or qualitative confidence statement rather than a bare number, once
enough is known about the input-level noise to estimate one.

---

## 7. Demand pressure

**[FLAW]** Inherits the same filtering asymmetry as §6 (same two inputs).
Reporting the ratio to two decimal places (1.03) implies more precision
than a single snapshot, built from a source with disclosed slide-to-slide
discrepancies (§3), can actually support.

**[MISLEAD]** A ratio very close to 1.0 (1.03) reads as "balanced" —
but given the demand-side inclusion of some already-served load (§4),
the *true* ratio of genuinely-outstanding demand to active supply could
plausibly be somewhat below 1.0 today. The direction of the known bias
(demand slightly overstated) means 1.03 is arguably an upper bound on
current pressure, not a best estimate — worth stating explicitly
wherever this ratio is presented, not just implied by the filtering
asymmetry buried in §4.

---

## 8. Queue attrition

Already well documented as a *cumulative*, not cohort/time-normalized,
ratio (`docs/metric_definitions.md`) — correctly caveated in the data
dictionary. Sharper framing:

**[FLAW] [CAUSATION]** Pooling 30 years of `q_date` vintages means an
old, largely-resolved cohort (e.g., projects that entered in the late
1990s and have long since either come online or been withdrawn) can
dominate the numerator without representing the risk profile of
*today's* active queue at all. Treating the pooled historical rate
(32%) as predictive of what will happen to projects currently active is
an extrapolation the data doesn't actually license — it describes what
happened to a 30-year blend of cohorts under a wide range of historical
market and regulatory conditions, not a forecast for the current cohort
under current conditions.

**[REDUNDANT]** Partial, suspected correlation with Queue Age (§9) via a
shared "vintage/maturity" pathway — see cross-cutting section below.

---

## 9. Queue age

**[FLAW]** This component measures *time since queue entry*, not *whether
a project is stalled* — despite `docs/risk_score_design.md`'s own stated
rationale for including it ("active projects that have sat in the queue
a long time without resolving... often indicate interconnection
bottlenecks, financing difficulty, or a stalled project"). A project
that entered in 2020 and has progressed steadily through every
interconnection study milestone looks **identical**, by this metric, to
one that entered in 2020 and has been completely dormant since. This is
a construct-validity gap: the metric's name and stated justification
promise something (stalled-ness) that its actual construction (elapsed
time only) cannot distinguish from its benign alternative (a normal,
lengthy, but progressing interconnection study).

**[ROBUSTNESS]** If Berkeley Lab's `ia_phase_raw`/`ia_phase_clean` fields
carry any information about interconnection-study milestone progress,
that would be a genuinely better basis for a "stalled" signal than raw
age alone — worth investigating before trusting this component's face
validity.

---

## 10. Procurement Risk Score

**[MISLEAD]** The name "Procurement Risk Score" implies something about
actual **procurement** — contract terms, pricing risk, counterparty
risk, PPA structuring, financing risk. What's actually measured is
entirely **interconnection-queue dynamics** (demand-vs-supply balance,
attrition, age). A corporate energy-procurement professional encountering
this name would reasonably expect it to speak to questions it cannot
actually answer.

**[UNSUPPORTED]** Zero demonstrated predictive validity. This score has
been computed for exactly one snapshot, ever. It has never been checked
against any real downstream outcome (e.g., did a high score in the past
precede an actual corporate procurement shortfall or delay?). Calling it
a "risk score" implies diagnostic or predictive power that has not been
established at all — today it's better described as a composite
*descriptive indicator*, not a validated risk measure.

**[FLAW] — a process finding, not just an analytical one.** `R/05_risk_score.R`'s
header comment states that 4 of `docs/risk_score_design.md`'s 5 open
questions were "resolved" on 2026-08-20: (1) keep both Demand Pressure
and Delivery Gap at half weight rather than dropping one, (2) higher
Queue Attrition = higher risk ("the conventional reading"), (3)
normalization uses provisional placeholder thresholds, (4) a missing
component is excluded and remaining weights rescaled. **`docs/decisions.md`
has no entry for any of these four specific decisions.** Its two actual
2026-08-20 entries cover different things entirely (the integrated
dataset being a single snapshot row, and `active_queue_mw` as the metric
base for Demand Pressure/Delivery Gap). `CLAUDE.md` states explicitly:
"Every methodological decision gets recorded in `docs/decisions.md`
before implementation proceeds." Question 2 in particular
(`risk_score_design.md`: *"needs Samantha's judgment, not just data"*)
appears to have been resolved by adopting the memo's own suggested
default ("the conventional reading") rather than through a documented
confirmation — the same kind of gap this project's own process already
caught and corrected once before, for a different reason, in
`docs/metric_definitions.md`'s missing-decisions-log finding. Worth
confirming directly whether these four were actually discussed and
simply left unlogged, or genuinely defaulted without confirmation.

**What to verify:** whether Samantha actually confirmed the attrition-
directionality reading and the other three items, and if so, backfill
`docs/decisions.md` entries for all four, consistent with the project's
own standing documentation requirement.

---

## 11. Normalization

Already self-disclosed as provisional/arbitrary throughout
(`docs/risk_score_design.md`, `R/05_risk_score.R` code comments) — real
credit for the honesty of that disclosure. Additional points:

**[FLAW]** `clip_0_100()` silently discards tail information. A Demand
Pressure Ratio of 4.9 and one of 20 both normalize to ~100 — the score
cannot distinguish "somewhat extreme" from "wildly extreme" once past
the placeholder ceiling, which matters a great deal if this score is
ever used to rank severity across multiple future snapshots.

**[FLAW]** Queue Attrition's linear 0–100% → 0–100 mapping has no stated
justification for linearity. It's equally plausible that attrition risk
is a threshold effect (e.g., "under 15% is unremarkable, over 40% is a
real red flag, with little difference in between") rather than a smooth
linear relationship — this project has not examined which shape is more
defensible.

**[UNSUPPORTED]** The composite score (31.2) is not interpretable in any
absolute sense today. Under equally arbitrary, equally defensible
alternative thresholds, this same underlying snapshot could just as
easily produce a score of 20 or 50. Nothing about "31.2" should be read
as meaning anything on its own — only the *relative* comparisons this
project has already been careful to frame (across weighting scenarios)
carry any information at all.

---

## 12. Weighting

**[FLAW]** The base-case "3 equal slots" allocation (demand-side 1/3,
attrition 1/3, age 1/3, with the demand-side slot further split in half
between its two redundant expressions) has no empirical or domain basis
— it's a subjective judgment call, and expressing it as clean fractions
(1/6, 1/6, 1/3, 1/3) gives it a veneer of mathematical precision it
hasn't earned.

**[FLAW]** The 3 sensitivity scenarios (`R/06_sensitivity_analysis.R`)
only ever move Demand Pressure and Delivery Gap *together*, by
construction (they're always given equal weight to each other in every
scenario). This is a reasonable simplification for isolating one axis
(demand-side vs. queue-side emphasis) — but it means the sensitivity
analysis structurally cannot reveal what happens if the two redundant
components were ever weighted *unequally* relative to each other, and it
never explores the full weight simplex (e.g., a scenario putting 100% of
weight on a single component).

---

## 13. Sensitivity analysis

**[FLAW]** The analysis tests sensitivity to **weighting choices only**.
It explicitly does **not** test sensitivity to the normalization
*thresholds* — which `docs/risk_score_design.md` itself identifies as
having no empirical basis at all (arguably a larger source of
uncertainty than the weighting scheme, since the weights at least sum to
a bounded, interpretable allocation, while the normalization ceilings
are pulled from nowhere in particular). `docs/risk_score_sensitivity_interpretation.md`
half-acknowledges this in passing — it deserves to be stated as a
limitation of the sensitivity analysis itself, not a footnote.

**[MISLEAD]** The observed swing across the 3 scenarios (30.0 to 33.5,
a 3.5-point range on a 0–100 scale) reads, at a glance, as reassuring —
"the score doesn't move much." **This would be a misleading conclusion
if generalized to "the score is reliable."** It only demonstrates
robustness to *one specific, narrow axis* of uncertainty (weight choice,
and only weight choice moved in the specific paired way §12 describes).
It says nothing about the score's sensitivity to the normalization
thresholds, which were held completely fixed throughout.

**[CAUSATION]** `primary_driver` was `delivery_gap` in **both** alternative
scenarios. This could look like a substantive finding ("delivery gap is
the score's most important lever") — but it may simply be a mechanical
artifact of how the scenarios are constructed: Demand Pressure and
Delivery Gap always move together (§12), and Delivery Gap's normalized
score (53) happens to be the highest of the four components this
snapshot, so whichever paired component's weight moves the most will
almost automatically show the largest contribution swing. This is worth
treating as a procedural artifact to investigate, not a data-driven
insight to report at face value.

---

## Redundant variables

**Demand Pressure Ratio ≡ Delivery Gap MW** — identical inputs
(`corporate_demand_mw`, `active_queue_mw`), expressed as a ratio and a
difference respectively. `docs/risk_score_design.md` already identified
this as the single most consequential finding in that memo, and the
half-weight fix reduces but does not eliminate the effect: both
components are near-perfectly correlated by construction, so together
they still contribute the equivalent of one fully-weighted, essentially
noiseless signal — while Queue Attrition and Queue Age are genuinely
independent measurements with their own separate uncertainty. The "fix"
addresses the arithmetic double-count; it doesn't address that this
pair's combined information content is inherently thinner than either
of the other two components individually (one snapshot, one ratio,
zero variance to date).

**Queue Attrition ↔ Queue Age (partial, suspected)** — both are
downstream of the same 30-year vintage/maturity pooling mechanism
(older cohorts have had more time both to resolve one way or another
*and* to accumulate age). `docs/risk_score_design.md` flagged this as
"worth checking empirically once both are computed" — it still cannot
be checked at all with a single snapshot (correlation requires
variation across multiple observations). This is a known, suspected
redundancy that remains completely untested, not a resolved non-issue.

---

## Confounding factors

- **Macroeconomic financing conditions** (interest rates, capital
  availability) plausibly affect both corporate data-center buildout
  decisions and generator-interconnection completion rates
  simultaneously — a shared external driver that could make demand and
  supply appear to move together (once a real time series exists) for
  reasons having nothing to do with grid readiness specifically.
- **ERCOT interconnection-process/policy changes** over the 30-year
  `q_date` window (ERCOT's own interconnection queue rules and study
  procedures have changed at various points historically) could shift
  pooled attrition and age patterns for *procedural* reasons unrelated
  to genuine grid-capacity dynamics — another confound baked into any
  cumulative 30-year pooled statistic.
- **Sector-specific demand cycles.** Data-center demand is plausibly
  driven substantially by AI/compute buildout cycles distinct from the
  economic cycles driving "industrial" or "other" sector demand — this
  project treats `data_center` as a single stable trend without
  accounting for that sector's own particular volatility.
- **Source-level reporting noise** (§3's disclosed 8,927/8,926 MW
  discrepancy) is itself a confound on precision — it means any small
  observed change, once repeated snapshots exist, could be pure
  reporting noise rather than a real shift in either demand or supply.

---

## Correlation vs. causation risks

- Even once a genuine demand-side time series exists, observing demand
  and supply move together would **not** establish that demand growth
  *causes* queue growth. Reverse causality is at least equally
  plausible: existing or planned generation capacity may itself be what
  *attracts* corporate data-center siting decisions in the first place
  (companies plausibly site large loads where they expect abundant,
  cheap, or reliable power) — supply could be driving demand's location
  choices as much as demand drives supply investment.
- Attrition and Age moving together (§ redundant variables, above)
  likely reflects a **shared vintage confound** — an old cohort that
  happens to have both high cumulative attrition and high average age —
  not two independently compounding risk signals. Reading the composite
  score's movement as "both attrition risk and age risk are
  contributing" could double-count what is really one underlying
  phenomenon (queue maturity).
- Any future observed correlation between the Procurement Risk Score and
  a real-world outcome (e.g., a corporate buyer failing to secure power
  on schedule) would **not** establish the score predicts or causes that
  outcome without genuine out-of-sample validation across many
  independent snapshots — something this project is nowhere near having.

---

## Claims the data cannot currently support

- Any claim about **clean-energy-specific** demand or supply dynamics
  (§0) — no generation-technology filter exists on either side of this
  analysis. **Addressed 2026-08-26** by renaming the project rather than
  adding filtering (`docs/decisions.md`) — this bullet now stands as a
  guardrail against the framing quietly creeping back in, not as an
  open violation.
- Any **trend, growth, or "widening gap"** claim — there is exactly one
  demand-side snapshot; no historical demand series exists to support
  any directional claim (the supply side does have real history; the
  demand side does not, and the two must never be conflated).
- Any **predictive-validity** claim for the Procurement Risk Score — it
  has never been validated against a real outcome.
- Any claim that ercotqueue.com's figures are **independently audited**
  or authoritative — self-flagged `[NEEDS VERIFICATION]` in this
  project's own data dictionary, never resolved.
- Any claim that the risk score is **"objective"** — normalization
  thresholds are explicitly arbitrary placeholders.
- Any claim at a **sub-ERCOT-region** grain (county, load zone) — not
  supported at all on the demand side, and not cross-checked on the
  supply side.
- Any claim that active queue MW constitutes **deliverable or guaranteed**
  capacity — the project's own existing hard guardrail, restated here
  explicitly as a claims-the-data-cannot-support item because it is the
  single easiest guardrail for external-facing material to accidentally
  violate.

---

## Additional robustness checks recommended

1. **Repeated monthly pipeline runs** (6–12 months) to build a genuine
   empirical distribution for normalization and enable real demand-side
   trend analysis — the single highest-value fix available, since it
   would resolve or substantially narrow §11, §13, and part of §3.
2. **Independently cross-check** ercotqueue.com's figures against
   ERCOT's original LLWG PPTX filing at least once, to resolve the
   standing `[NEEDS VERIFICATION]` flag.
3. **Sensitivity-test the normalization thresholds themselves**, not
   just the weights — e.g., vary the Demand Pressure ceiling from 3.0×
   to 8.0× and observe how much the composite score moves, the same way
   `R/06_sensitivity_analysis.R` already does for weights.
4. **Test the attrition-directionality assumption** by inverting its
   sign in the composite score and observing the swing, given §10's
   finding that this was a genuinely open question the design memo
   flagged for confirmation.
5. **Recompute the headline ratio using `total_queue_mw` instead of
   `active_queue_mw`** as a framing-sensitivity check. Back-of-envelope
   from the real executed numbers: this alone would move the Demand
   Pressure Ratio from ~1.03 to roughly ~0.53 (420,812 / 791,939) — a
   larger swing than the entire 3-scenario weighting sensitivity
   analysis produced (30.0–33.5). The choice of supply-side denominator
   is, by this measure, a bigger lever on the headline finding than
   anything tested so far.

   **Acted on 2026-08-26** (`docs/decisions.md`) — Samantha adopted
   `total_queue_mw` as the actual metric base, not just a sensitivity
   check. Re-running the pipeline under the new formula confirmed the
   swing was, if anything, understated here: Delivery Gap MW flips sign
   entirely (+13,400 → −371,127 MW) and overshoots
   `R/05_risk_score.R`'s normalization range outright, saturating
   `norm_delivery_gap` to exactly `0` and silently losing all magnitude
   information for that component — a live, concrete instance of the
   `clip_0_100()` tail-information-loss risk this critique's Normalization
   section (§11) had only described hypothetically. See
   `docs/risk_score_sensitivity_interpretation.md`'s Results section for
   the full numbers.
6. **Spot-audit** a sample of Berkeley Lab `region=='ERCOT'` rows against
   known project names/locations, and re-verify the 854-row missing-
   `state` count against the real executed `queued_up_clean.csv`.
7. **A falsification/placebo check** — confirm that the `data_center`
   sector's specific pattern actually differs meaningfully from a sector
   that shouldn't carry the same large-corporate-load signal (e.g.,
   "industrial" or "other"), as a sanity check that this project's
   headline figures aren't just picking up generic queue-wide movement.
8. **Concentration risk check** — compute what share of `active_queue_mw`
   is attributable to the single largest active project. A denominator
   that could swing substantially on one project's status change (e.g.,
   one large wind farm being withdrawn) is fragile in a way the current
   single-snapshot analysis cannot reveal.

---

## Summary table

| # | Area | Top finding | Category | Severity |
|---|---|---|---|---|
| 0 | Cross-cutting | "Clean energy" was not operationalized anywhere in the pipeline — **resolved 2026-08-26 by renaming the project**, not by adding filtering | FLAW, UNSUPPORTED | High (resolved) |
| 1 | Dataset integration | "Integration"/"reconciliation" imply more cross-validation than exists | MISLEAD | Medium |
| 2 | Geographic alignment | Real strength (region alignment), but unaudited region tags + shifting ERCOT footprint over time | FLAW | Low–Medium |
| 3 | Time alignment | Demand-side figure is also cumulative, not a clean point-in-time reading | FLAW, MISLEAD | Medium |
| 4 | Demand definition | `corporate_demand_mw` includes already-energized/operating load | FLAW, UNSUPPORTED | **High** |
| 5 | Queue-capacity definition | No locational/deliverability information at all | FLAW, UNSUPPORTED | Medium |
| 6 | Delivery gap | Nets two non-equivalent queue types; false precision | FLAW, MISLEAD | **High** |
| 7 | Demand pressure | Same asymmetry as #6; likely an upper bound, not a best estimate | FLAW, MISLEAD | Medium |
| 8 | Queue attrition | 30-year pooling conflates vintage cohorts; not predictive of current cohort | FLAW, CAUSATION | Medium |
| 9 | Queue age | Measures elapsed time, not stalled-ness — construct-validity gap | FLAW | Medium |
| 10 | Procurement Risk Score | 4 of 5 design-memo decisions never logged in decisions.md | FLAW (process) | **High** |
| 11 | Normalization | Score (31.2) is not interpretable in absolute terms today | UNSUPPORTED | Medium |
| 12 | Weighting | "3 equal slots" has no empirical basis; scenarios can't test unequal redundant-pair weighting | FLAW | Low–Medium |
| 13 | Sensitivity analysis | Tests weights only, not normalization — narrow swing could be over-read as "robust" | FLAW, MISLEAD | Medium |
| — | Redundant variables | Demand Pressure ≡ Delivery Gap; Attrition↔Age suspected, untestable at n=1 | REDUNDANT | Medium |
| — | Robustness | Total-vs-active-queue swap alone moves the ratio more than the whole sensitivity analysis did | ROBUSTNESS | **High** |

**The four findings marked "High" severity are the ones most worth
addressing before this project's numbers are presented externally**:
the unoperationalized "clean energy" framing (§0 — already resolved by
the 2026-08-26 rename, see `docs/decisions.md`), the demand-side
already-served-load inclusion (§4), the headline Delivery Gap's false
precision (§6), and the undocumented risk-score design decisions (§10)
— plus the robustness finding that the active-vs-total queue choice
alone swings the headline ratio more than anything tested so far.
