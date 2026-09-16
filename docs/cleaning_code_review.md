# Cleaning Pipeline Code Review

Independent review of `R/01_import_clean.R` (both the ERCOTQueue.com and
Berkeley Lab "Queued Up" pipelines) against ten risk categories: incorrect
assumptions, silent row deletion, incorrect joins, date conversion
problems, geographic inconsistencies, duplicate handling problems,
potential many-to-many joins, hard-coded assumptions, unnecessary
transformations, and reproducibility problems.

Reviewed 2026-08-20. **No code was modified in this pass** — review only.

## Methodology note

Both scripts remain unexecuted in this environment (R was only installed
today, and required packages aren't installed yet). Every finding below
comes from static reading — R/dplyr semantics, cross-referencing
documented data facts (`docs/data_dictionary.md`,
`docs/data_reconnaissance.md`, `docs/decisions.md`), and reasoning through
what specific inputs would trigger each behavior — not from actually
running the code. Severity reflects the assessed impact *if* the
described mechanism is correct. Where a finding's mechanism is
well-established (documented R/library behavior) vs. merely plausible,
that's noted explicitly — treat the distinction as a signal for how
urgently to verify empirically once the pipeline actually runs.

---

## 1. Date conversion problems

### Finding 1.1 — [FIXED 2026-08-20] Berkeley Lab date columns risk an off-by-one-day shift depending on the machine's timezone

**Location:** `prepare_berkeley_lab_ercot()`, the
`dplyr::across(c(q_date, prop_date, on_date, wd_date, ia_date), as.Date)`
call.

**Why this could be a problem:** readxl's documented behavior is to
represent Excel date cells as **POSIXct at midnight UTC**, regardless of
the workbook's own timezone context (readxl's own documentation states it
treats Excel dates as UTC). `as.Date()` applied to a POSIXct value with no
`tz` argument converts using `tz = ""` — the **system's local
timezone** — not UTC. So a cell meaning "2026-01-21" becomes a POSIXct
instant at `2026-01-21 00:00:00 UTC`, and on a machine set to any
timezone behind UTC (US Eastern, Central, Pacific, etc.), converting that
instant to local wall-clock time lands on the evening of 2026-01-20, so
`as.Date()` reads off `2026-01-20` — every date one day early, silently,
with no warning or error.

**How detrimental:** every date field in the Berkeley Lab clean CSV
(`q_date`, `prop_date`, `on_date`, `wd_date`, `ia_date`, plus derived
`q_year`) could be systematically off by one day depending purely on
which machine runs the script. This directly threatens the temporal
alignment decision in `docs/decisions.md` (2026-08-19) — "cumulative
entered by `q_date <= ERCOT_as_of_date`" — a date near the `as_of_date`
boundary could flip which side of the cutoff it falls on. It's also a
reproducibility problem in its own right: the same code run on different
machines with different timezone settings could produce different
`q_date` values from the identical source file.

**What to verify:** once the script runs, pick 3–5 known `q_id`s and
spot-check their `q_date`/`on_date`/`wd_date` in the output CSV against
the raw Excel cell's displayed date (open the workbook directly). Also
check `Sys.timezone()` on whichever machine runs the pipeline.

**Recommended fix:** replace `as.Date` with a timezone-explicit
conversion — `as.Date(x, tz = "UTC")` for each of the five date columns
(or swap the whole `across()` call to `lubridate::as_date()`, which
handles this correctly by default). A one-line-per-call fix.

**Fixed 2026-08-20:** `prepare_berkeley_lab_ercot()` now applies
`as.Date(.x, tz = "UTC")` to all five date columns. Prioritized after
`/code-review` on `R/03_data_integration.R` reconfirmed this bug
specifically threatens the `q_date <= as_of_date` cutoff that script
depends on, and — more importantly — that the integration's own
reconciliation checks can't detect the misclassification if it occurs
(they stay internally consistent regardless of a systematic date shift).
Still unverified by actual execution — R packages aren't installed yet —
but the "what to verify" spot-check above still applies once they are.

### Finding 1.2 — [LOW] ERCOTQueue date parsing relies on R's default ISO 8601 assumption with no explicit format

**Location:** `flatten_load_projects()`, `as.Date(last_seen_date_raw)` /
`as.Date(last_changed_date_raw)`.

**Why this could be a problem:** these calls parse character strings
with no `format =` argument, so R assumes `"%Y-%m-%d"`. This matches
ercotqueue.com's actual format today (confirmed:
`"last_seen_date": "2026-01-21"`).

**How detrimental:** not a live bug. If the source ever changes date
format, every record would fail to parse and get routed to `excluded`
(these fields are in `validate_load_projects()`'s `.exclude` criteria) —
a loud, 100%-exclusion failure, not silent corruption, so the blast
radius is self-limiting.

**What to verify:** nothing urgent. If a future refresh's quality report
ever shows all 8 records excluded, check `last_seen_date`/
`last_changed_date` format first.

**Recommended fix:** optional — add `format = "%Y-%m-%d"` explicitly to
self-document the assumption rather than relying on R's default.

---

## 2. Silent row deletion

### Finding 2.1 — [Already fixed, noted for completeness] The Berkeley Lab `region` filter's NA-drop risk

**Location:** `prepare_berkeley_lab_ercot()`.

Caught by `/code-review` earlier this session and already fixed in the
current code — `region` is normalized (trimmed, blank-to-NA) before the
ERCOT filter runs, and `n_region_missing` is tracked as its own metric
rather than being silently folded into "non-ERCOT" rows. Confirmed still
correct on this re-read. No further action.

### Finding 2.2 — [LOW, no live impact] `flag_duplicate_q_id_entity`'s correctness depends on an unstated ordering guarantee

**Location:** `flag_berkeley_lab_quality_issues()`,
`dplyr::add_count(q_id, entity, ...)`.

**Why this could be a problem:** this runs on `clean_tbl` — post-
exclusion, so `q_id`/`entity` are guaranteed non-NA by that point (both
are hard exclusion criteria in `validate_berkeley_lab_queue()`). That's
correct today, but the guarantee is implicit — it relies on function call
order in `clean_queued_up_data()`, not enforced or asserted at the point
of use. dplyr's grouping treats `NA == NA` as a match for grouping
purposes, so if this function were ever called on unvalidated data, rows
with missing `q_id`/`entity` would be silently grouped together as
false-positive "duplicates."

**How detrimental:** currently none — the guarantee holds today. Risk is
purely about future refactoring (e.g., someone calling
`flag_berkeley_lab_quality_issues()` directly on unvalidated data).

**What to verify:** nothing now.

**Recommended fix:** low priority — a defensive
`stopifnot(!anyNA(clean_tbl$q_id), !anyNA(clean_tbl$entity))` at the top
of the function would make the dependency explicit rather than implicit.

---

## 3. Incorrect joins / 7. Potential many-to-many joins

### Finding 3.1 — [INFORMATIONAL — N/A today, real forward-looking risk] Neither script performs a join

**Why this could be a problem:** no `*_join()` calls exist in either
pipeline — each cleans one source independently, so this category
doesn't apply to the *current* code. It's worth stating the guardrail
explicitly here anyway, since a composite/join script is the obvious next
step, and `docs/decisions.md` (2026-08-19) already mandates the answer:
**"two independently-aggregated, ERCOT-wide totals in parallel... Not a
row-level join."** There is no shared key (Berkeley Lab's `q_id` is
project-level; ERCOT Large Load's `record_id` is an aggregate-bucket ID)
and the grain mismatch (3,757 rows vs. 8 rows) has no principled
resolution.

**How detrimental if ignored later:** joining on any constant shared
value (e.g., if a future script added a `region` column to both and
joined on it) would fan out to 3,757 × 8 = 30,056 duplicated rows — the
classic many-to-many explosion.

**What to verify:** nothing in current code.

**Recommended fix:** N/A for current code. When a composite/join script
is eventually written, treat `docs/decisions.md`'s "not a row-level join"
mandate as a hard constraint, and re-run this review's join-specific
categories against that script when it exists.

---

## 4. Geographic inconsistencies

### Finding 4.1 — [LOW, currently a no-op] `flag_state_not_tx` cannot fire against current data, by construction

**Location:** `flag_berkeley_lab_quality_issues()`.

**Why this could be a problem:** `docs/data_reconnaissance.md` already
established (2026-08-17) that the 854 `region=='ERCOT'` rows with
`state != 'TX'` are **all** actually rows with `state` missing, not
genuinely different state values. So `flag_state_not_tx`
(`!is.na(state) & state != "TX"`) is guaranteed to evaluate to 0 rows
today — not incorrect, but its code comment ("if any occur") slightly
undersells that this has already been checked and found structurally
impossible today, not merely unobserved.

**How detrimental:** none — documentation-clarity note, not a
correctness issue. Still useful as insurance against a future refresh
introducing genuine cross-boundary state values.

**What to verify:** nothing.

**Recommended fix:** optional — tighten the code comment to state this
explicitly.

### Finding 4.2 — [LOW] No cross-check between `county` (name) and `fips_code` (numeric code)

**Why this could be a problem:** these two fields should correspond 1:1
for a given row, but nothing in the pipeline verifies that — a
data-entry error assigning a mismatched FIPS code to a county name would
pass through undetected.

**How detrimental:** low today (no evidence this occurs in the source),
but would matter if `fips_code` is later used for a join to
county-level EIA/NREL/DSIRE context data — a wrong code would silently
misattribute a row's geography.

**What to verify:** once the script runs, spot-check whether
`county`/`fips_code` pairs look internally consistent (e.g., against a
standard FIPS-to-county-name reference for a sample of rows).

**Recommended fix:** low priority given no current evidence of a
problem; if this matters for a future join, add a cross-check against a
canonical county/FIPS reference and flag (not drop) mismatches, same
pattern as the rest of the pipeline.

### Finding 4.3 — [LOW] `fips_code` zero-padding has no upper-bound check

**Location:** `prepare_berkeley_lab_ercot()`, `sprintf("%05d", ...)`.

**Why this could be a problem:** `sprintf("%05d", ...)` pads to a
*minimum* of 5 digits — it would not catch or flag a malformed 6+-digit
value, it would just print all of them.

**How detrimental:** none currently (confirmed range 48001–48507, all
clean 5-digit values). The zero-padding step just doesn't defend against
this class of future bad data the way other fields in this pipeline do
(flag-not-drop).

**What to verify:** nothing now.

**Recommended fix:** optional — add a flag column (e.g.
`flag_fips_wrong_length`) for any populated `fips_code` that isn't
exactly 5 characters after padding, consistent with this pipeline's
existing flag-don't-drop pattern.

---

## 5. Duplicate handling problems

### Finding 5.1 — [MEDIUM] The `(q_id, entity)` duplicate key has no real discriminating power within the ERCOT subset, even though it's the documented key file-wide

**Location:** `flag_berkeley_lab_quality_issues()`.

**Why this could be a problem:** the LBNL codebook's rationale for
combining `q_id` with `entity` is to disambiguate `q_id`s that repeat
across *different* balancing authorities/entities (confirmed file-wide:
`q_id` repeats ~7,902 times across different entities). But within
`region=='ERCOT'`, `entity` is effectively constant (ERCOT is a single
balancing authority) — so `flag_duplicate_q_id_entity` is, in practice,
just testing `q_id` uniqueness alone for this subset. It correctly
reports 0 duplicates today, but that's because `q_id` alone is already
unique within ERCOT (confirmed via fresh inspection), not because the
composite key is doing meaningful disambiguation work here — the
mechanism that makes `(q_id, entity)` necessary file-wide doesn't apply
within a single-entity subset.

**How detrimental:** currently none (0 duplicates confirmed either way).
Matters only if a future refresh somehow introduces genuine `q_id`
collisions within ERCOT — the current check would still catch that, so
this is more a conceptual clarity issue than a live bug.

**What to verify:** nothing now.

**Recommended fix:** none required functionally; consider a code comment
noting that within ERCOT this check is effectively a `q_id` uniqueness
check, so a future reader doesn't assume it's testing cross-entity
collisions that can't occur in this subset.

### Finding 5.2 — [LOW] A duplicate flag has no group size/ID if it ever fires

**Why this could be a problem:** `flag_duplicate_q_id_entity` is a bare
boolean — if duplicates existed, there'd be no way to tell from the
clean CSV alone how many rows are in each duplicate cluster or which
rows belong together, beyond re-deriving it from `q_id`/`entity` directly.

**How detrimental:** low — inconvenient, not incorrect.

**What to verify:** nothing now (0 duplicates today).

**Recommended fix:** low priority — if this pipeline is ever run against
data with real duplicates, consider adding a `duplicate_group_id` (e.g.,
via `dplyr::cur_group_id()`) alongside the boolean flag.

---

## 6. Reproducibility problems

### Finding 6.1 — [MEDIUM] Raw source snapshots aren't preserved anywhere, so a specific historical analysis result can't be exactly reproduced later

**Why this could be a problem:** `data/README.md` documents `data/raw/`
as gitignored ("not committed... all are re-fetchable from the original
sources"). For Berkeley Lab this is fine — it's a static file placed
manually. For **ERCOT Large Load, `import_ercot_large_load()` re-fetches
from the live ercotqueue.com URL every time the script runs** — a re-run
next month pulls whatever `as_of_date` is current then, overwriting the
same raw file path. This is intentional per `docs/decisions.md`
(2026-08-19: "must be re-derived from the live `as_of_date`... not
hardcoded"), but the consequence is that once ercotqueue.com's live data
moves past a given snapshot, that exact snapshot can never be
regenerated.

**How detrimental:** medium — doesn't affect the correctness of any
single run, but means "reproduce Figure X from the June 2026 analysis"
isn't literally possible once the live source has moved on, which
matters for a project whose stated goal includes analytical rigor and
portfolio defensibility.

**What to verify:** confirm this tradeoff is the intended one — it may
well be, given the decision was made deliberately, but worth explicitly
deciding whether "current-state only, not historically reproducible" is
acceptable, vs. wanting an exception to the gitignore-raw-data policy for
this specific small JSON (unlike the 15MB Berkeley Lab Excel file,
snapshotting every fetched JSON wouldn't meaningfully bloat the repo).

**Recommended fix (pending a decision, not applied here):** consider
timestamp-versioning fetched ERCOT Large Load JSON (e.g.
`load_queue_summary_2026-08-20.json` alongside the canonical path the
pipeline reads), and/or committing those small JSON snapshots to git as
a deliberate exception to the general raw-data policy — specifically
because they're small, and because the "current state" framing already
established in `docs/decisions.md` makes snapshot history analytically
meaningful here in a way it isn't for Berkeley Lab's static file.

### Finding 6.2 — [LOW] No package version pinning

**Why this could be a problem:** neither script records the R/package
versions it was written against (no `renv.lock`, no captured
`sessionInfo()`). Behavior could vary subtly across dplyr/readxl/jsonlite
versions on different machines — readxl's date-guessing heuristics and
dplyr's type-strictness have both changed across versions historically.

**How detrimental:** low today, but compounds with Finding 1.1 as a
source of cross-machine inconsistency.

**What to verify:** once packages are installed, capture `sessionInfo()`
output somewhere (e.g., appended to `docs/AI_WORKFLOW.md`) so the exact
versions used for any given analysis are on record.

**Recommended fix:** optional, but worth considering `renv::init()` for
this project given its stated emphasis on reproducibility.

### Finding 6.3 — [MEDIUM, ties to Finding 1.1] Validation logic has never been exercised against a real failing row

**Location:** both `validate_load_projects()` and
`validate_berkeley_lab_queue()`.

**Why this could be a problem:** both functions are designed so that,
against today's actual data, 0 rows are expected to fail every check —
which means the exclusion machinery itself (the actual `dplyr::filter`/
`case_when` logic) has never been proven to behave correctly when
triggered. Stated honestly in both functions' docstrings, but still an
untested code path.

**How detrimental:** medium — if the exclusion logic itself has a bug
(e.g., a typo in a column name inside `case_when`), it wouldn't surface
until the day it's actually needed, at which point trusting its output
requires faith rather than verification.

**What to verify:** once R packages are installed, run each
`validate_*()` function against a small hand-built synthetic tibble with
one deliberately bad row per check (missing `q_id`, an out-of-vocabulary
`q_status`, an unparseable date) and confirm each one routes to
`excluded` with the expected `exclusion_reason`.

**Recommended fix:** write this as a small ad hoc verification script
the first time R actually runs this code, before trusting the pipeline
on the real files.

---

## 8. Hard-coded assumptions

### Finding 8.1 — [MEDIUM] `skip = 1` (the title-row offset) is a silent-corruption risk if the workbook's layout ever changes

**Location:** `read_berkeley_lab_raw()`.

**Why this could be a problem:** if Berkeley Lab ever adds a second
title row above the header in a future refresh, `read_excel(..., skip = 1)`
would then read what's actually the real header row as data, and treat
the *next* row (real data) as column names — producing plausible-looking
but wrong column names, not an error. Nothing downstream currently
checks that the read-in column names match the expected 30-column set
before proceeding.

**How detrimental:** high *if* it ever happens (silent, not loud — the
opposite of Finding 1.2's self-limiting failure mode), but low
probability — this is a manually-downloaded file's layout stability, not
a live API that changes format without notice.

**What to verify:** after the first real run, confirm all 30 expected
column names are present in `read_berkeley_lab_raw()`'s output.

**Recommended fix:** add an explicit assertion in
`read_berkeley_lab_raw()` — compare `names()` against the expected
30-column set and `stop()` with a clear message if they don't match,
rather than silently proceeding with wrong headers.

### Finding 8.2 — [Informational, cross-referenced] Controlled vocabularies are hardcoded, quoted from source documentation

`QUEUE_STATUS_LEVELS`, `TYPE_1_LEVELS`, `LOAD_PROJECTS_SECTOR_LEVELS` are
hardcoded, quoted from the LBNL codebook / ercotqueue.com docs. This is
acceptable, low-risk hardcoding — any new value the source ever
introduces gets flagged via the `.unexpected_*` checks, not silently
dropped or silently accepted. Listed here only because this review
explicitly asked to check for hard-coded assumptions — this category has
a safety net, unlike Finding 8.1.

---

## 9. Unnecessary transformations

### Finding 9.1 — [Informational, not a problem] Defensive re-coercion of already-correctly-typed columns

`prepare_berkeley_lab_ercot()`'s `as.numeric()` pass over
`mw_1`/`mw_2`/`mw_3` and `as.integer()` over `q_year`/`prop_year` is very
likely a no-op — readxl already returns these as numeric/double. Listed
here because this review explicitly asked about unnecessary
transformations, but this is intentional defensive coding (makes the
type contract explicit rather than implicit) and costs nothing
meaningful. Not recommending removal.

### Finding 9.2 — [Informational, not a problem] Constant `region` column retained in Berkeley Lab's clean CSV

Always `"ERCOT"` after filtering, technically redundant. Kept
deliberately for self-description — a reader opening
`queued_up_clean.csv` in isolation can see its scope without external
context. Not recommending removal.

---

## Summary table

| # | Finding | Category | Severity |
|---|---|---|---|
| 1.1 | `as.Date()` on POSIXct without `tz="UTC"` — possible off-by-one-day shift | Date conversion / reproducibility | Fixed 2026-08-20 |
| 1.2 | ERCOTQueue date parsing assumes ISO 8601, no explicit format | Date conversion | Low |
| 2.1 | Region-filter NA-drop risk | Silent row deletion | Fixed |
| 2.2 | Duplicate-flag NA-safety depends on implicit call order | Silent row deletion | Low |
| 3.1 | No joins exist yet; forward-looking many-to-many risk documented | Joins | Informational |
| 4.1 | `flag_state_not_tx` is a structural no-op today | Geographic | Low |
| 4.2 | No county/fips_code cross-check | Geographic | Low |
| 4.3 | `fips_code` padding has no upper-bound check | Geographic | Low |
| 5.1 | `(q_id, entity)` key has no real power within single-entity ERCOT | Duplicates | Medium |
| 5.2 | Duplicate flag has no group ID | Duplicates | Low |
| 6.1 | Raw ERCOT snapshots not preserved — historical results not reproducible | Reproducibility | Medium |
| 6.2 | No package version pinning | Reproducibility | Low |
| 6.3 | Validation/exclusion logic never exercised against a failing row | Reproducibility | Medium |
| 8.1 | `skip = 1` has no post-read schema assertion | Hard-coded assumptions | Medium |
| 8.2 | Hardcoded controlled vocabularies (has a safety net) | Hard-coded assumptions | Informational |
| 9.1 | Defensive re-coercion of already-typed columns | Unnecessary transformations | Informational |
| 9.2 | Constant `region` column retained | Unnecessary transformations | Informational |

Finding 1.1 was fixed 2026-08-20 (see that finding's entry above) after
`/code-review` on `R/03_data_integration.R` reconfirmed it directly
threatens the integration script's temporal cutoff. All other findings
remain as documented — this was originally a review-only
deliverable, per request.
