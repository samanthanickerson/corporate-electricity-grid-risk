# Final Code Review — R Pipeline

Senior-level review of all nine R scripts in `R/` (3,455 lines), conducted
2026-09-04, after the pipeline has executed end to end.

**No code, data, or output was modified.** This is a review document.

## Scope and method

Every script was read in full: `R/01_import_clean.R` (817),
`R/03_data_integration.R` (246), `R/04_metrics.R` (278),
`R/05_risk_score.R` (409), `R/06_sensitivity_analysis.R` (399),
`R/07_visualizations.R` (660), `R/08_manual_validation_sample.R` (356),
`R/09_tableau_export.R` (165), `R/10_top_risk_regions.R` (125).

Where a risk could be tested rather than asserted, it was tested against
the actual executed outputs:

| Hypothesis | Method | Result |
|---|---|---|
| The functions duplicated across `R/05`/`R/06`/`R/08` have drifted apart | Extracted and diffed all 8, comments stripped | **No drift** — currently identical |
| Duplicate `(q_id, entity)` rows are double-counted in MW totals | Counted `flag_duplicate_q_id_entity` in the cleaned data | **0 duplicates today** |
| `NA` `mw_1` values are silently summed as zero | Counted `NA` `mw_1` in `queued_up_clean.csv` | **0 today** — the risk is latent, not active |
| Non-positive `mw_1` is handled consistently | Traced the 5 flagged rows through `R/03`, `R/05`, `R/07` | **Inconsistent** — see MEDIUM-3 |
| Joins introduce many-to-many risk | Searched for `*_join()` on analytical data | **No analytical joins exist** |
| Results depend on random state | Searched for `set.seed`/`sample`/`runif`/`rnorm` | **None** — fully deterministic |
| Errors are handled | Searched for `tryCatch`/`withCallingHandlers`/`on.exit` | **None anywhere** |

**Relationship to the existing review documents.** This complements rather
than repeats `docs/cleaning_code_review.md` (2026-08-20 — `R/01` only,
static analysis, written before R had ever run) and the per-script
`/code-review` passes recorded in `docs/AI_WORKFLOW.md`. This review covers
all nine scripts, cross-script consistency, and behavior now observable
from real output.

## Severity summary

| Tier | Count | Theme |
|---|---:|---|
| CRITICAL | **0** | No defect currently producing incorrect published results |
| HIGH | 4 | Latent correctness risks and structural fragility |
| MEDIUM | 8 | Robustness, consistency, and reproducibility gaps |
| LOW | 6 | Polish and maintainability |

---

## CRITICAL — none found

No issue in this codebase is currently producing an incorrect published
number. This tier is left empty deliberately rather than by promoting a
lesser finding into it.

The basis for that conclusion: the four duplicated-function sets are
byte-identical; there are no duplicate rows being double-counted; there
are no `NA` MW values being silently zeroed; the composite score
recomputes by hand to the published 21.03; and the integration
reconciliation checks close to zero. The HIGH findings below are real and
worth fixing, but each is a *latent* risk — a way this pipeline could
silently produce wrong numbers after a future change or data refresh, not
evidence that it has.

---

## HIGH

### HIGH-1 · Eight functions triplicated across three scripts with nothing enforcing they stay identical

**Where:** `R/05_risk_score.R` (canonical), duplicated into
`R/06_sensitivity_analysis.R` and `R/08_manual_validation_sample.R` —
`clip_0_100()`, `normalize_attrition()`, `normalize_demand_pressure()`,
`normalize_delivery_gap()`, `normalize_queue_age()`,
`compute_composite_score()`, `weighted_median()`, `compute_queue_age()`,
plus `compute_metrics()` copied from `R/04_metrics.R` into `R/08`.
Additionally, `R/06`'s `SENSITIVITY_SCENARIOS$base_case`
(`R/06:183-186`) hand-restates the weights from `RISK_SCORE_WEIGHTS`
(`R/05:38-43`).

**Why it matters:** I verified these are identical *today*, so nothing is
wrong right now. But the only thing keeping them in sync is a comment
asking future maintainers to update three files at once. If
`normalize_delivery_gap()` were changed in `R/05` alone, the sensitivity
analysis would silently be testing a different model than the one in
production — which directly undermines CLAUDE.md's guardrail that the
score must always be presented alongside its sensitivity results. The
`base_case` weights are the sharpest version of this: a change to
`RISK_SCORE_WEIGHTS` would make the "base case" scenario stop being the
base case, with no error.

**How to fix:** Extract the shared pure functions into a
`R/00_shared_functions.R` that the three scripts `source()`. These
functions have no side effects, so sourcing them carries none of the risk
that motivated the duplication in the first place — that risk came from
sourcing whole *pipeline* scripts, which execute on load (see HIGH-2).
If the duplication is kept deliberately, add an assertion in `R/06` and
`R/08` comparing `deparse(body(f))` against the `R/05` original, and
compare `SENSITIVITY_SCENARIOS$base_case` to `RISK_SCORE_WEIGHTS`
directly.

### HIGH-2 · Every script runs its full pipeline on `source()`

**Where:** the last lines of all nine scripts — `R/01:810,813,816`,
`R/03:244`, `R/04:276`, `R/05:408`, `R/06:398`, `R/07:659`, `R/08:355`,
`R/09:164`, `R/10:124`.

**Why it matters:** there is no way to load a script's functions without
also executing its work. Consequences: (a) it is the direct cause of
HIGH-1 — the functions had to be copy-pasted because `source()`-ing
`R/05` would re-run the scoring pipeline and rewrite
`procurement_risk_scores.csv`; (b) an accidental `source("R/01...")` in an
interactive session triggers a live network fetch and overwrites both raw
and processed data; (c) it makes the code untestable by any standard R
testing framework.

**How to fix:** guard the execution block in each script:

```r
if (sys.nframe() == 0) {
  result <- run_risk_score_pipeline()
  print(result)
}
```

Sourcing then loads functions only; `Rscript R/05_risk_score.R` still runs
the pipeline exactly as before.

### HIGH-3 · `R/01` re-fetches and overwrites raw data on every run, contradicting the project's own immutability rule

**Where:** `R/01_import_clean.R:50-62` (`fetch_and_save_json()` →
`writeBin()`), invoked unconditionally at `R/01:810`.

**Why it matters:** `docs/decisions.md` (2026-08-15) states raw source
files "are treated as immutable, and are never edited in place." The code
does not honor that: every execution re-downloads both JSON files and
overwrites `data/raw/ercot_large_load/`. Because ercotqueue.com is a live
source whose `as_of_date` advances, re-running `R/01` can silently replace
the analysis input with a different snapshot — and since `data/raw/` is
gitignored, the prior snapshot is then unrecoverable. Every published
figure is specific to `as_of_date` 2026-06-18; nothing in the code
protects that anchor.

**How to fix:** make the fetch conditional —
`fetch_and_save_json(url, refresh = FALSE)` that returns the existing path
when the file is present, requiring an explicit `refresh = TRUE` to
re-download. Better still, write date-stamped filenames
(`load_queue_summary_2026-06-18.json`) so snapshots accumulate rather than
overwrite, which would also make the repeated-snapshots future work in
`README.md` straightforward.

### HIGH-4 · Duplicate queue rows are detected but never acted on, and the reconciliation check cannot catch the consequence

**Where:** flag computed at `R/01:637-638`
(`add_count(q_id, entity)` → `flag_duplicate_q_id_entity`); totals summed
without reference to it at `R/03:123-127`; reconciliation at
`R/03:195-200`.

**Why it matters:** the cleaning pipeline correctly identifies duplicate
`(q_id, entity)` pairs and — per the project's "never silently drop
records" rule — flags rather than removes them. But no downstream stage
consults the flag. `R/03` sums `mw_1` across every in-scope row, so a
duplicated project's capacity would be counted twice in `total_queue_mw`,
propagating into the attrition rate, demand pressure ratio, delivery gap,
and composite score. The reconciliation check at `R/03:195-200` cannot
detect this, because the duplicate is present on both sides of the
subtraction and cancels out. There are 0 duplicates today, so no current
figure is affected — this is a trap for a future data refresh.

**How to fix:** in `R/03`, fail loudly when
`sum(berkeley_lab$flag_duplicate_q_id_entity) > 0`, forcing an explicit
decision about deduplication rather than silently double-counting. If
duplicates are ever legitimate in this source, deduplicate on
`(q_id, entity)` before aggregating and record the row count in the
reconciliation report.

---

## MEDIUM

### MEDIUM-1 · No stage-order or file-existence guards anywhere

**Where:** every `readr::read_csv()` / `readxl::read_excel()` call — e.g.
`R/03:39-46`, `R/04:246`, `R/05:293-294`, `R/07:608-610`, `R/09:48-50`,
`R/10:37-38`. No script calls `file.exists()`.

**Why it matters:** these scripts are strictly ordered, but nothing
enforces it. Running `R/04` before `R/03` — or anything at all on a fresh
clone, where `data/processed/` is gitignored and absent — produces an
opaque readr "does not exist" error rather than "run `R/03` first." The
scripts are otherwise careful to fail with specific, actionable messages
(`R/03:60-74`, `R/09:51-74`), so this is an inconsistency in their own
standard.

**How to fix:** a small shared helper —
`require_input(path, produced_by = "R/03_data_integration.R")` — that
checks existence and `stop()`s with the name of the script that produces
the missing file. Natural companion to the shared-functions file proposed
in HIGH-1.

### MEDIUM-2 · `na.rm = TRUE` masks missing capacity, including in the check meant to catch it

**Where:** `R/03:123-127` (the five MW totals), and `R/03:197-200` (the
`mw_check` reconciliation).

**Why it matters:** a row with `NA` `mw_1` contributes 0 MW to the totals
but still counts in `n_projects_in_scope`, so capacity could go missing
with no visible signal. The reconciliation check that ought to catch this
applies `na.rm = TRUE` on both sides of the subtraction, so `NA` values
cancel and it reports 0 regardless — the check is weaker than it looks.
There are 0 `NA` `mw_1` rows today, so nothing is currently lost.

**How to fix:** count `NA` `mw_1` rows explicitly and report the count as
its own row in the reconciliation report, so "0 missing" is asserted
rather than assumed.

### MEDIUM-3 · Non-positive `mw_1` is handled three different ways across three scripts

**Where:** `R/03:123-127` includes them in every sum; `R/05:56` (inside
`weighted_median()`) drops rows where `w <= 0`; `R/07:123` (inside
`build_monthly_cumulative()`) drops them and reports the count in each
chart caption.

**Why it matters:** five ERCOT rows carry `mw_1 <= 0` and are flagged and
retained by design (`flag_nonpositive_mw_1`). But `total_queue_mw` counts
them, the MW-weighted queue-age median excludes them, and the trend charts
exclude them and disclose it. Three effective samples, three behaviors,
none of them wrong on its own — but the divergence isn't documented
anywhere, so a reader reconciling the queue-age sample size (1,760) against
the in-scope project count (3,608) has no stated reason for the difference
beyond the active-status filter.

**How to fix:** state the intended treatment once in
`docs/metric_definitions.md` and reference it from each of the three sites,
or normalize the behavior. No calculation needs to change — the
inconsistency is in the documentation, not the arithmetic.

### MEDIUM-4 · Provisional normalization thresholds are hard-coded in three files

**Where:** `max_ref = 5.0`, `scale = 200000`, `max_ref = 3650` — defined
identically at `R/05:142,176,186`, `R/06:117,124,131`, and
`R/08:156,165,172`.

**Why it matters:** these are the most consequential magic numbers in the
project; they set the entire 0–100 scale of the composite score, and they
are explicitly documented as arbitrary placeholders awaiting calibration.
Having them in three places means recalibration is a three-file edit with
no check that all three moved together — the HIGH-1 drift risk, applied to
the numbers most likely to change.

**How to fix:** promote to named constants in the shared-functions file
proposed in HIGH-1 (`DEMAND_PRESSURE_MAX_REF`, `DELIVERY_GAP_SCALE`,
`QUEUE_AGE_MAX_REF`) so recalibration is a single edit.

### MEDIUM-5 · `normalize_demand_pressure()` remains calibrated for a superseded formula

**Where:** `R/05:126-147` — the docstring at `R/05:133-141` flags this
explicitly.

**Why it matters:** the `0–5.0` reference range was chosen when Demand
Pressure Ratio was computed against `active_queue_mw`. The 2026-08-26
decision changed the denominator to `total_queue_mw`, which is always
larger, so the same real-world conditions now yield a systematically
smaller ratio (~1.03 → ~0.53). The ceiling was never revisited. The code
correctly documents this rather than hiding it, and it is a known,
deliberately-deferred item — but it remains an open miscalibration
affecting a published component score (10.63).

**How to fix:** recalibrate against the `total_queue_mw` scale, or apply
the same bounded `tanh` treatment already adopted for the delivery gap.
Either way, record it in `docs/decisions.md` and re-run the sensitivity
analysis afterward.

### MEDIUM-6 · Region and state labels are hard-coded independently of the filter that defines them

**Where:** `R/03:116` (`geography = "ERCOT"`), `R/09:118`
(`state_for_map = "Texas"`), `R/10:97` (interpolated into the `note`).

**Why it matters:** `R/01:539` performs the actual scope filter
(`region == "ERCOT"`). The label written into every downstream file is a
separate literal that would not follow if that filter ever changed. `R/09`
and `R/10` now guard against this (`R/09:104-110` stops if `geography`
is not `"ERCOT"`), but `R/03` — where the literal originates — does not.

**How to fix:** derive `geography` in `R/03` from the data
(`unique(in_scope$region)`, asserted to be length 1) rather than
hard-coding it, so the label cannot disagree with the filter.

### MEDIUM-7 · No package version pinning, and one unstated minimum version

**Where:** no `renv.lock` in the repository; `R/07:144` uses
`dplyr::cross_join()`, introduced in dplyr 1.1.0.

**Why it matters:** results depend on whatever package versions happen to
be installed. `cross_join()` is the concrete case — the visualization
script fails outright on dplyr < 1.1.0, with nothing declaring that
requirement.

**How to fix:** initialize `renv` and commit `renv.lock`. At minimum,
document the tested R and package versions in `README.md`.

### MEDIUM-8 · No error handling, timeout, or retry on the network fetch

**Where:** `R/01:54-58`; no `tryCatch` exists anywhere in the codebase.

**Why it matters:** `httr::stop_for_status()` correctly turns an HTTP
error status into a failure, but a hung connection has no timeout and a
transient failure has no retry — a momentary network problem aborts the
whole pipeline with a low-level error. Given this is the only external
dependency in the project, it is the most likely runtime failure point.

**How to fix:** add `httr::timeout(30)` to the `GET()` call and wrap the
fetch in a short retry with a clear message naming the URL that failed.

---

## LOW

### LOW-1 · Inconsistent figure resolution
`R/06:392` saves at `dpi = 150` while `R/07:95` uses `dpi = 300`. One of
the eleven figures in `output/figures/` is half the resolution of the
other ten. **Fix:** raise `R/06` to 300.

### LOW-2 · Relative paths assume the working directory
Every path is relative to the project root (`"data/processed/..."`), so
scripts fail if run from any other directory. **Fix:** use `here::here()`,
or document the requirement in `README.md`.

### LOW-3 · Undeclared package dependency
`R/09` and `R/10` call `tibble::tibble()` without `library(tibble)`
(`R/09:38-39`, `R/10:30`). This works, but the dependency isn't visible in
the header where every other script declares it. **Fix:** add the
`library()` call for consistency.

### LOW-4 · Edge case in the structural-missingness report
`R/01:705-710` classifies a field as structurally missing when its
`NA` count equals `nrow(clean_tbl)`. On an empty table every field would
qualify. **Fix:** guard with `nrow(clean_tbl) > 0`.

### LOW-5 · Numbering gap at `R/02`
The sequence runs `01`, `03`–`10`. Harmless, but it reads as a missing
stage to anyone new. **Fix:** note the gap in `README.md`, or renumber.

### LOW-6 · The duplicated `compute_metrics()` drops its explanatory comments
`R/08`'s copy is code-identical to `R/04:52-155` but omits the comment
blocks explaining the div-by-zero guards and the `total_queue_mw`
decision. The copy is therefore harder to audit than the original.
**Fix:** copy the comments too, or resolve via HIGH-1.

---

## Verdict by review dimension

Every dimension requested, with an explicit assessment — including the
ones where nothing was found.

| Dimension | Verdict | Notes |
|---|---|---|
| **Readability** | Strong | Consistent structure across all nine scripts: constants, small documented functions, an orchestrator, then execution. Roxygen-style docstrings throughout. |
| **Reproducibility** | Mixed | Deterministic and well-staged, but undermined by no package pinning (MEDIUM-7), gitignored data, and a live source that overwrites its own input (HIGH-3). |
| **Naming conventions** | Strong | snake_case throughout; `R/01:440-448` standardizes source column names generically rather than by hardcoded rename list. Internal flags consistently prefixed `.`/`flag_`/`is_`. |
| **Hard-coded values** | Needs work | Normalization thresholds triplicated (MEDIUM-4); region/state labels decoupled from the filter (MEDIUM-6); paths assume working directory (LOW-2). |
| **File paths** | Adequate | Relative and consistent, but no `here::here()` and no existence checks (MEDIUM-1, LOW-2). |
| **Error handling** | Needs work | Good `stop()` guards on structural assumptions (28 across 8 scripts) — but zero `tryCatch`, no timeout/retry on the only network call (MEDIUM-8), and no stage-order guards (MEDIUM-1). |
| **Missing-value handling** | Mostly strong | Genuinely careful: every `normalize_*()` returns `NA_real_` (never 0) for non-finite input; `%in%` used over `==` at `R/01:619-623` specifically for NA-safety; `compute_metrics()` checks each div-by-zero and missing-input case explicitly. Weakened by blanket `na.rm = TRUE` in the aggregation step (MEDIUM-2). |
| **Duplicate handling** | Needs work | Detected and flagged correctly, never enforced downstream (HIGH-4). |
| **Join logic** | N/A — by design | The pipeline contains no analytical joins. The two sources are combined as parallel aggregates via scalar extraction (`R/03:58-80`), a documented decision (`docs/decisions.md`, 2026-08-19) driven by the absence of any shared key. The only `left_join` (`R/07:154`) is an internal month-grid fill, not a data integration. |
| **Many-to-many joins** | No risk | Follows from the above — there is no join that could fan out. The one `left_join` joins against a `cross_join`-generated grid guaranteed unique on `(month, status)`. |
| **Statistical calculations** | Sound, with documented caveats | Verified: the composite recomputes to the published 21.03; `weighted_median()` (`R/05:55-67`) correctly uses the ≥50% cumulative-weight definition; the `tanh` normalization behaves as documented at ±scale. Interpretive caveats (provisional thresholds, pooled attrition, subjective weighting) are disclosed in the code and `docs/`. MEDIUM-5 is the one open calibration issue. |
| **Comments** | Excellent | The strongest aspect of this codebase. Comments explain *why*, cite decisions by date, and record failed approaches — e.g. `R/01:513-519` explains that `dplyr::if_else()` evaluates both branches eagerly, which defeated a first attempt at the FIPS fix. `R/05:149-175` documents both the bug and the reasoning behind its replacement. |
| **Function reuse** | Mixed | Strong within scripts (`build_single_value_chart()` serves 4 charts; `build_monthly_cumulative()` serves 4 more; both quality-report builders read from already-computed flags rather than recomputing predicates). Poor across scripts — HIGH-1. |
| **Package dependencies** | Adequate | Eight packages, all mainstream, each `library()`-declared where used except LOW-3. No pinning (MEDIUM-7). |
| **Unnecessary code** | Minimal | No dead code found. `.n_id_entity` (`R/01:637`) is created and dropped intentionally. Prior review passes already removed an unused `library(dplyr)` from `R/10`. |
| **Potential bugs** | 4 latent, 0 active | All four HIGH findings are latent-failure modes rather than present defects; see the CRITICAL section for the evidence behind that distinction. |

---

## What is already sound

Worth stating explicitly, because these are the practices that kept the
severity of everything above low:

- **No silent record drops.** Both cleaning pipelines route failing rows to
  an `excluded` table with a documented `exclusion_reason` rather than
  filtering them away (`R/01:231-272`, `R/01:570-598`), and questionable-
  but-valid rows are flagged and retained rather than deleted
  (`R/01:612-652`). Each pass emits a quality report with before/after
  counts.
- **Executable self-tests.** Five `validate_*()` functions run hand-built
  examples through the same code paths used on real data and `stop()` on
  mismatch. `validate_metric_formulas()` caught a real arithmetic error
  during development.
- **Each stage writes a new file.** No stage mutates an earlier stage's
  output, so any step can be re-run and inspected independently.
- **Missing values are never silently coerced to zero** in the scoring
  layer — a missing component is excluded and the remaining weights
  rescaled, with the exclusion recorded in the output.
- **Defensive structural assertions.** Single-row and single-value
  expectations are asserted with specific error messages rather than
  assumed (`R/03:60-74`, `R/07:625-630`, `R/09:51-74`, `R/10:41-60`).
- **Accessible, consistent figures.** `R/07:49-66` fixes a colorblind-safe
  Okabe-Ito palette to status categories, with a separate palette for
  indicators so no color carries two meanings.
- **Charts disclose their own exclusions.** Every trend chart reports the
  count of records excluded for non-positive MW in its caption
  (`R/07:119-125`), rather than quietly dropping them.

---

## Suggested remediation order

Ordered by benefit relative to effort:

1. **HIGH-2** (`main()` guards) — smallest change, and it unblocks HIGH-1.
2. **HIGH-1** (shared functions file) — removes the largest structural
   risk; naturally absorbs MEDIUM-4 and LOW-6.
3. **HIGH-4** (duplicate assertion in `R/03`) — a few lines; closes the
   only path to a silently wrong headline number.
4. **HIGH-3** (conditional fetch) — protects the snapshot the published
   figures depend on.
5. **MEDIUM-1, -2, -6** — robustness and provenance; all small.
6. **MEDIUM-7** (`renv`) — mechanical, and the single biggest improvement
   to reproducibility.
7. **MEDIUM-5** (recalibration) — the only item requiring a methodological
   decision, so it belongs with the analyst rather than in a cleanup pass.
8. **MEDIUM-3, -8 and the LOW items** — polish.

Items 1–4 are the ones that meaningfully reduce the risk of this pipeline
ever publishing a wrong number.
