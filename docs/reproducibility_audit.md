# Reproducibility Audit

An assessment of whether a new analyst who has just cloned this repository
could reproduce the project, conducted 2026-09-04.

**Reproducibility score: 54 / 100** — thoroughly documented, not currently
runnable. Full rubric and arithmetic below.

**Nothing was modified.** This is an audit document; every issue is
reported with a recommended fix, not fixed.

## Method

This audit was run against **what a clone actually contains** — the output
of `git ls-files` — rather than against the local working directory, which
holds many files that are gitignored and therefore invisible to anyone
else. That distinction turned out to matter more than any other factor
here.

Repository-wide: 61 tracked files, 38 of them under `composite_data_info/`.

### What a fresh clone gets

| Present | Detail |
|---|---|
| All 9 R scripts | `R/01`, `R/03`–`R/10` |
| 11 of the 12 documents | Decision log, data dictionary, metric definitions, both code reviews, analytical critique, AI workflow log, and more. (This audit is the 12th and is not yet committed.) |
| Project documentation | `README.md`, `CLAUDE.md`, `data/README.md` |
| All 3 Tableau specifications | `tableau/README.md`, `dashboard_design.md`, `build_steps.md` |
| **All 6 analysis outputs** | `output/analysis/*.csv`, including `top_risk_regions.csv` and `risk_score_sensitivity.csv` — so the headline results and the complete sensitivity table are readable **without running anything** |

### What a fresh clone does *not* get

| Absent | Consequence |
|---|---|
| `data/raw/` (entire directory) | Neither ERCOT JSON nor the Berkeley Lab `.xlsx` — no pipeline stage can run |
| `data/processed/` (entire directory) | No `integrated_analysis.csv`, no `procurement_risk_scores.csv`, and **no `tableau_final.csv`** |
| `output/figures/` | None of the 11 PNGs |

Excluding `data/` from version control is a deliberate, documented decision
(`docs/decisions.md`, 2026-08-15) with a sound rationale: the files are
large and some are licensed for non-redistribution. This audit does not
treat that as an error. It does flag the consequence, which is not
currently mitigated: without committed data, reproduction depends entirely
on the acquisition instructions — and those are the weakest part of the
repository.

---

## The blocker a new analyst hits first

**The analysis is not the repository root.**

At the time of this audit the project lived as one subdirectory inside a
larger private repository that also held unrelated personal work. The
analytics project was therefore not what a clone landed in, and there was
no README at the repository root explaining where it was.

This has two distinct consequences:

1. **Reproducibility.** Every path in every R script is relative to the
   project directory (`"data/processed/..."`, `"output/figures/..."`).
   A new analyst's natural working directory after cloning is the
   repository root, where every one of those paths resolves to nothing.
   The scripts fail immediately with file-not-found errors that give no
   hint that the fix is to change directory first.
2. **Presentation.** A reader given that repository's URL would not land
   on the analysis at all. The work is careful; the packaging did not
   present it as the point.

**Recommended fix (highest value in the audit, and requires no code
change):** publish the analysis as its own repository. Doing so resolves
the path problem for free — the project directory becomes the repository
root, so every relative path in the R scripts is correct from the clone
directory.

---

## Criterion-by-criterion assessment

### 1. Required packages — 5/10

**Evidence.** Eight packages are used: `httr`, `jsonlite`, `dplyr`,
`tibble`, `purrr`, `readr`, `readxl`, `stringr`, plus `ggplot2` and
`scales` for figures. Each is declared with `library()` at the top of every
script that uses it — that part is done properly and consistently.

**Gaps.** There is no `renv.lock` and no version pinning of any kind. There
is no `install.packages()` line anywhere in the repository, so a new
analyst must read all nine scripts to assemble the dependency list
themselves. `R/07:144` uses `dplyr::cross_join()`, which requires dplyr
≥ 1.1.0 — an unstated hard requirement that fails on older installations.
The R version actually used (4.6.1) appears only incidentally inside two
`docs/AI_WORKFLOW.md` session entries, not in any setup documentation.

**Fix.** Initialize `renv` and commit `renv.lock`. Failing that, add a
setup block to `README.md` with a single `install.packages(c(...))` call
and the tested R version.

### 2. File paths — 5/10

**Evidence.** Paths are relative, consistent, and predictable throughout
(`data/processed/…`, `output/analysis/…`, `output/figures/…`). No absolute
paths or machine-specific paths appear anywhere — a genuine strength.

**Gaps.** All of them assume the working directory is
`composite_data_info/`, which — as described above — is *not* the clone
root. No script uses `here::here()` or otherwise resolves paths relative to
a project root, and no document states the working-directory requirement.

**Fix.** Document the requirement explicitly in `README.md`, or adopt
`here::here()` with a `.here` sentinel file so scripts work from anywhere
in the tree.

### 3. Data availability — 3/10

**Evidence.** The demand-side ERCOT JSONs are fetched automatically by
`R/01` — genuinely self-service, with the source URL, license (CC BY 4.0),
and `robots.txt` status documented in the script header.

**Gaps.** The supply-side Berkeley Lab workbook is a manual download that
is not present in the clone. Neither raw nor processed data is committed,
so nothing at all can run until that file is obtained. Worse for exact
reproduction: because the ERCOT source is live and `R/01` re-fetches and
overwrites on every run (`docs/final_code_review.md`, HIGH-3), a new
analyst running the pipeline today receives a *newer* snapshot than the one
every published figure describes. The `as_of_date` 2026-06-18 results are
therefore not reproducible by re-running, even with the correct workbook.

**Fix.** Commit a date-stamped copy of the ERCOT JSON snapshot (small, and
CC BY 4.0 — redistribution is permitted), which would make the demand side
exactly reproducible. See criterion 10 for the workbook.

### 4. Instructions — 2/10

**Evidence.** `README.md` documents the methodology, the pipeline stages
and their purposes, findings, and limitations thoroughly.

**Gaps.** It contains **no setup or execution instructions of any kind**. A
search for install / setup / prerequisites / how-to-run / clone / reproduce
/ `Rscript` returns nothing. There is no Makefile, no run-all script, no
`LICENSE`, and no `.Rproj`. A new analyst is told what each script *does*
but never told how to run one, in what environment, or in what order to
execute the full pipeline.

**Fix.** Add a "Getting started" section: prerequisites (R version,
packages), data acquisition (criterion 10), the working-directory
requirement, and the literal command sequence. This is the single
highest-leverage documentation change available.

### 5. Script order — 7/10

**Evidence.** The numeric prefixes make execution order essentially
self-documenting, and `README.md`'s methodology table lists all nine
scripts in order with a one-line purpose for each. Each script's header
comment names the files it reads and writes.

**Gaps.** There is no orchestrator — no Makefile, no `run_all.R` — so the
order must be followed by hand. The sequence skips `02`, which reads as a
missing stage to anyone new and is explained nowhere. And the order is not
strictly linear: `R/08` (validation sample) and `R/10` (findings table) are
side branches, while `R/09` depends on `R/06`'s output as well as `R/05`'s
— facts a newcomer can only discover by reading the code.

**Fix.** Add a `run_all.R` that sources the stages in order, and either
explain the `02` gap or renumber.

### 6. Dependencies between scripts — 7/10

**Evidence.** Dependencies are real and traceable: every stage reads only
persisted files and writes new ones, so the chain is inspectable, and each
script's header states its inputs and outputs explicitly. Several scripts
assert their structural expectations loudly (`R/03:60-74`, `R/09:51-74`,
`R/10:41-60`).

**Gaps.** The dependency graph exists only in prose. No script checks
whether its inputs exist before reading them — running out of order
produces a raw readr error rather than "run `R/03` first"
(`docs/final_code_review.md`, MEDIUM-1). And because every script executes
on `source()` (HIGH-2 in that review), a new analyst experimenting by
sourcing a file to inspect its functions will instead silently re-run a
pipeline stage and overwrite outputs.

**Fix.** Add existence guards naming the producing script, and wrap
execution blocks in `if (sys.nframe() == 0)`.

### 7. Output locations — 9/10

**Evidence.** Output locations are consistent and predictable:
`data/processed/` for datasets, `output/analysis/` for tables,
`output/figures/` for charts. Critically, `output/analysis/` **is
committed** — so a new analyst can read `top_risk_regions.csv`,
`risk_score_sensitivity.csv`, `manual_validation_sample.csv`, both quality
reports, and the integration reconciliation without running anything. That
is the single most useful reproducibility decision in the repository, and
it is what keeps this audit's score from falling much lower.

**Gaps.** `output/figures/` is gitignored, so none of the 11 charts are
viewable in a clone; a reader must run the pipeline to see any
visualization. Given the figures are small PNGs derived from committed
data, that exclusion buys little.

**Fix.** Commit `output/figures/`, or embed two or three key charts in
`README.md`.

### 8. Documentation — 10/10

**Evidence.** This is the project's outstanding dimension, and it is not
close. A clone includes: a 16-entry decision log with rationale,
alternatives, and revisit conditions for every methodological choice; a
data dictionary with per-field provenance and explicit
`[NEEDS VERIFICATION]` flags; formula definitions with hand-verified
worked examples; a deliberately skeptical analytical critique of the
project's own methods; **two** independent code reviews; a 32-entry
AI-collaboration log recording what was decided by the analyst versus
implemented by the assistant, including scope conflicts and reversed
decisions; and three Tableau specification documents.

Interpretation is separated from observation, caveats travel with the
figures they qualify, and superseded decisions are marked rather than
deleted. A new analyst can reconstruct not just *what* was done but *why*,
and what was considered and rejected.

**Gaps.** None material to reproducibility. The only wrinkle is volume —
some orientation guidance about which document to read first would help,
though `README.md` largely serves that role.

### 9. Tableau dataset — 4/10

**Evidence.** All three specification documents are committed and are
unusually complete: a field-by-field data dictionary for the export, a
three-dashboard design with chart types, KPIs, filters, tooltips and
subtitle language, and click-by-click build steps including calculated-field
formulas.

**Gaps.** **`data/processed/tableau_final.csv` is not in the clone.**
`tableau/README.md` opens by naming it as the file the dashboards should
connect to, but it lives in a gitignored directory. A new analyst holding
complete build instructions cannot build anything until they have solved
the data-acquisition problem and run the full pipeline. The second data
source the specs reference, `output/analysis/risk_score_sensitivity.csv`,
*is* committed — so the sensitivity chart is buildable while the other
eight worksheets are not.

**Fix.** Commit `tableau_final.csv`. It is a single row of derived,
non-licensed values, it is the documented handoff artifact between the R
pipeline and the dashboard layer, and committing it would make the entire
Tableau half of this project reproducible on its own.

### 10. Source-data instructions — 2/10

**Evidence.** The ERCOT side is well handled: source URLs, license,
`robots.txt` status, and the automated fetch are all documented in
`R/01`'s header and `docs/decisions.md`. The Berkeley Lab file's expected
filename and worksheet are documented (`docs/data_dictionary.md:15`,
`docs/data_reconnaissance.md:34`), and `README.md` links to
`emp.lbl.gov/queues`.

**Gaps.** This is where reproduction actually breaks.

- **No acquisition procedure.** Nothing states "download X from Y and save
  it to `data/raw/berkeley_lab/Queued_Up_Data.xlsx`." The path is
  inferable from the code, but a new analyst must reverse-engineer it.
- **No edition or vintage is identified.** Berkeley Lab republishes
  *Queued Up* annually. Nothing records which release produced the 3,757
  ERCOT rows this analysis is built on. Downloading the current edition
  will silently yield different totals — different attrition, different
  queue age, a different composite score — with no warning that the inputs
  diverged.
- **`data/README.md` is misleading on this exact point.** It states raw
  files are "all re-fetchable from the original sources above," which is
  true for the JSONs but not for the manual workbook. It also documents
  `procurement.db` and a `scripts/` GIS fetch, neither of which exists —
  so the first orientation document a new analyst reads describes
  infrastructure that was never built.
- **Failure is non-atomic.** With the workbook missing, `R/01` fetches and
  *overwrites* both JSONs before erroring on `read_excel`, leaving raw data
  in a modified state after a failed run.

**Fix.** Add an explicit acquisition section to `data/README.md`: the
download URL, the exact release/edition and its publication date, the
expected filename and destination path, a file checksum if practical, and
the worksheet name. Correct the "all re-fetchable" claim and remove the
`procurement.db` and `scripts/` references. Recording the edition matters
most — without it, exact reproduction is impossible even for someone who
does everything else right.

---

## Score: 54 / 100

Weighted so the number is auditable rather than a summary impression.
Weights reflect how much each criterion actually determines whether a new
analyst can reproduce the work.

| Criterion | Weight | Score /10 | Weighted |
|---|---:|---:|---:|
| Required packages | 10 | 5 | 5.0 |
| File paths | 10 | 5 | 5.0 |
| Data availability | 15 | 3 | 4.5 |
| Instructions | 15 | 2 | 3.0 |
| Script order | 10 | 7 | 7.0 |
| Dependencies between scripts | 10 | 7 | 7.0 |
| Output locations | 5 | 9 | 4.5 |
| Documentation | 15 | 10 | 15.0 |
| Tableau dataset | 5 | 4 | 2.0 |
| Source-data instructions | 5 | 2 | 1.0 |
| **Total** | **100** | | **54.0** |

### Why 54 and not higher

Three things cap this score, and none of them is about analytical quality:

1. **Nothing runs out of the box.** The pipeline cannot execute until a
   new analyst obtains an undocumented file from an unidentified edition of
   an external dataset.
2. **There are no instructions to run it.** No setup section, no command
   sequence, no dependency install, no stated working directory.
3. **The published figures cannot be reproduced even in principle**, because
   the demand source is live and the pipeline overwrites its own raw
   snapshot on each run.

### Why 54 and not lower

The documentation is genuinely exceptional and carries full marks —
a decision log, data dictionary, metric definitions, a self-critique, two
code reviews, and an honest AI-collaboration log. Committing
`output/analysis/*.csv` was the right call and does real work: **the
headline findings, the full sensitivity analysis, both data-quality
reports, and the integration reconciliation are all readable in a clone
without running a line of code.** A reviewer can audit the reasoning and
verify the arithmetic end to end. That is a meaningful form of
reproducibility, and many repositories with runnable code offer far less
of it.

The honest summary: **a new analyst could fully understand this project
today, and could verify its conclusions from committed outputs — but could
not re-execute it, and could not regenerate its exact numbers.**

---

## What a new analyst *could* do today, with no additional information

- Read the research question, methodology, findings, and limitations in
  `README.md`.
- Verify the headline numbers directly from `output/analysis/top_risk_regions.csv`
  and confirm the composite score by hand from the documented weights.
- Inspect the full 3-scenario sensitivity analysis in
  `output/analysis/risk_score_sensitivity.csv`.
- Check the formula logic against hand-built worked examples in
  `output/analysis/manual_validation_sample.csv` and
  `docs/metric_definitions.md`.
- Audit data cleaning decisions via both quality reports and the
  integration reconciliation.
- Follow every methodological decision, including reversed ones, through
  `docs/decisions.md`.
- Read the two code reviews and the analytical critique to understand the
  project's known weaknesses.
- Build one of nine Tableau worksheets (the sensitivity chart, whose data
  source is committed).

They could **not**: run any script, regenerate any dataset, view any
figure, build the main dashboards, or reproduce the published figures.

---

## Prioritized fixes

Ordered by score improvement per unit of effort. None requires changing
analytical code.

| # | Fix | Criteria improved | Effort |
|---|---|---|---|
| 1 | Publish the analysis as its own repository, so the project directory becomes the repository root. | File paths, Instructions | Low |
| 2 | Add a "Getting started" section to `README.md`: R version, `install.packages()` call, working directory, and the literal command sequence. | Instructions, Packages, Script order | Low |
| 3 | Document Berkeley Lab acquisition in `data/README.md` — URL, **edition and publication date**, destination path, worksheet — and correct the stale "all re-fetchable" / `procurement.db` / `scripts/` claims. | Source-data instructions, Data availability | Low |
| 4 | Commit `data/processed/tableau_final.csv` and a date-stamped copy of the ERCOT JSON snapshot. | Tableau dataset, Data availability | Low |
| 5 | Commit `output/figures/`. | Output locations | Low |
| 6 | Add `renv.lock`. | Packages | Medium |
| 7 | Add a `run_all.R` and input-existence guards naming the producing script. | Script order, Dependencies | Medium |

**Items 1–4 alone would raise the score to roughly 80**, and none of them
touches a line of analytical code — they are packaging and documentation
changes. Items 6–7 overlap with HIGH-2 and MEDIUM-1/-7 in
`docs/final_code_review.md`.

The gap this audit measures is not a gap in analytical rigor. By that
standard the project is strong. It is a gap in packaging: careful work that
has not yet been made portable to anyone but its author.

---

## Addendum — 2026-09-09: items 1–5 completed

This audit was written 2026-09-04 as a point-in-time assessment. The score
of 54/100 above is left unchanged as the record of what a new analyst
found on that date. Since then, **all five Low-effort items have been
done:**

| # | Item | Status |
|---|---|---|
| 1 | Standalone repository | Done — published as `corporate-electricity-grid-risk`, with the project directory as the repository root |
| 2 | "Getting started" in `README.md` | Added — R 4.6.1, one `install.packages()` call, working directory, the literal command sequence |
| 3 | Berkeley Lab acquisition in `data/README.md`; correct stale claims | Added — URL, sheet, save path, edition (requests through end of 2025), download date, expected shape, and a version check. `procurement.db`, `scripts/fetch_ercot_gis.R`, and the `/qa` skill are now marked "not built" |
| 4 | Commit `tableau_final.csv` and a date-stamped ERCOT snapshot | Both committed. The snapshot is at `data/raw/ercot_large_load/snapshot_2026-06-18/` under its CC BY 4.0 license, and `R/01` now seeds a fresh clone from it |
| 5 | Commit `output/figures/` | All 11 charts committed; every figure reference in the documentation resolves |

**One finding turned out to be worse than this audit recorded.** Criterion
"Data availability" noted that the demand-side endpoint is live and
unpinned. It did not catch that `R/01` also *overwrote* the local snapshot
on every run — so re-running the pipeline destroyed the analysis input
rather than merely failing to pin it. That is now fixed (see
`docs/decisions.md`, 2026-09-09), and the demand side reproduces exactly
from the committed snapshot.

**Items 6 and 7 remain open:** no `renv.lock`, no `run_all.R`, and no
input-existence guards. Both are Medium effort and both overlap with open
findings in `docs/final_code_review.md`.

The estimate above — that items 1–4 alone would put the score near 80 —
was made before these changes and has not been re-tested by a fresh
reproduction attempt. Treat it as this audit's own prediction, not as a
new measured score. A re-audit from a clean clone is the honest way to
establish the current number.
