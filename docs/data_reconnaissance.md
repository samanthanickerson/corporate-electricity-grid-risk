# Data Reconnaissance

Read-only inspection of the Berkeley Lab raw file in `data/raw/`.
**No data was modified, cleaned, or transformed** — this is inspection
only, using `pandas`/`openpyxl` to read the file as-is. Field definitions
are quoted from its own on-sheet documentation (`04. Data Codebook`,
`00. Background + Methods`), not inferred from field names. Anything not
covered by that documentation is marked **[NEEDS VERIFICATION]**.

Inspected 2026-08-17. (This document originally also covered the CEBA
Deal Tracker PDF; that source and its findings were removed from the
project — see `docs/AI_WORKFLOW.md` for the history.)

---

## `data/raw/berkeley_lab/Queued_Up_Data.xlsx`

Workbook with **41 sheets** (14.85 MB). 40 sheets are Berkeley Lab's own
pre-aggregated national summary/trend tables (annual requests, capacity by
type/region/year, completion-rate trends, etc.) — not raw records. The one
record-level dataset is **`03. Complete Queue Data`**, which the checklist
below covers. An on-sheet codebook (`04. Data Codebook`) and methodology
notes (`00. Background + Methods`) are quoted directly rather than guessed.

**Scope, per `00. Background + Methods` (quoted/summarized):** data
collected by Interconnection.fyi from 7 ISOs/RTOs and 50 non-ISO balancing
areas (~98% of installed U.S. capacity); includes only bulk-power-system
(transmission-connected) interconnection requests, not distribution or
behind-the-meter; requests submitted through end of 2025; cleaned/QA'd by
LBNL and Interconnection.fyi.

| Item | Finding |
|---|---|
| File name | `Queued_Up_Data.xlsx`, sheet `03. Complete Queue Data` |
| Number of rows | 38,201 data rows |
| Number of columns | 30 |
| Column names | `q_id, q_status, q_date, prop_date, on_date, wd_date, ia_date, IA_phase_raw, IA_phase_clean, county, state, fips_code, poi_name, region, project_name, utility, entity, developer, cluster, service, project_type, type_1, type_2, type_3, type_clean, mw_1, mw_2, mw_3, q_year, prop_year` |
| Data types (as read by pandas) | 5 datetime64 (`q_date, prop_date, on_date, wd_date, ia_date`); 5 float64 (`fips_code, mw_1, mw_2, mw_3, q_year, prop_year` — 6 actually, see note below); the rest string/object. `fips_code`, `q_year`, `prop_year` are numeric identifiers/years stored as float64, not int, because of embedded missing values. |
| Missing-value counts | See table below. |
| Unique-value counts for categorical fields | See table below. |
| Potential geographic fields | `state`, `region`, `county`, `fips_code`, `poi_name` |
| Potential date fields | `q_date, prop_date, on_date, wd_date, ia_date` (+ derived `q_year, prop_year`) |
| Potential capacity/MW fields | `mw_1, mw_2, mw_3` |
| Technology fields | `type_1, type_2, type_3, type_clean`, `project_type` |
| Status fields | `q_status`, `IA_phase_raw`, `IA_phase_clean` |
| Potential identifiers | `q_id` (per codebook, combine with `entity`) — see Potential Duplicates below; this combination is **not** reliably unique. |
| Potential duplicate records | 0 fully-duplicate rows. **270 rows** sit in **135 duplicate `(q_id, entity)` groups** — e.g. `entity='Duke'` has two different rows both with `q_id='1'`, with different project names/capacities. This contradicts the codebook's claim that `q_id` + `entity` forms a unique identifier. |
| Potentially problematic fields | `fips_code` (float64, drops leading zeros — see below); `IA_phase_raw` (1,184 non-standardized free-text values, not usable for grouping — use `IA_phase_clean` instead); `q_id` (contains one literal placeholder value `'not assigned'`, and repeats ~7,902 times across different entities, so is meaningless alone). |
| Obvious inconsistencies | Status/date logic mismatches — see below. `region=='ERCOT'` vs. `state=='TX'` mismatch — see below. |

### Missing-value counts (full)

| Field | Missing | % of 38,201 |
|---|---:|---:|
| q_id | 0 | 0% |
| q_status | 0 | 0% |
| q_date | 665 | 1.7% |
| prop_date | 5,265 | 13.8% |
| on_date | 34,492 | 90.3% |
| wd_date | 22,578 | 59.1% |
| ia_date | 33,368 | 87.4% |
| IA_phase_raw | 14,738 | 38.6% |
| IA_phase_clean | 7,167 | 18.8% |
| county | 2,063 | 5.4% |
| state | 1,235 | 3.2% |
| fips_code | 1,770 | 4.6% |
| poi_name | 2,813 | 7.4% |
| region | 0 | 0% |
| project_name | 25,113 | 65.7% |
| utility | 7,855 | 20.6% |
| entity | 0 | 0% |
| developer | 29,714 | 77.8% |
| cluster | 25,806 | 67.6% |
| service | 10,797 | 28.3% |
| project_type | 1,224 | 3.2% |
| type_1 | 0 | 0% |
| type_2 | 33,144 | 86.8% |
| type_3 | 38,091 | 99.7% |
| type_clean | 0 | 0% |
| mw_1 | 0 | 0% |
| mw_2 | 37,105 | 97.1% |
| mw_3 | 38,156 | 99.9% |
| q_year | 665 | 1.7% |
| prop_year | 5,265 | 13.8% |

Most of this missingness is **expected, not a defect**: `on_date`/`ia_date`/
`wd_date` are conditional on project status (per codebook); `project_name`/
`developer`/`cluster` are explicitly noted in the codebook as "not
available for most requests"; `mw_2`/`mw_3` are hybrid-project-only fields.

### Unique-value counts for categorical fields

| Field | Unique values |
|---|---:|
| q_status | 5 |
| IA_phase_raw | 1,184 |
| IA_phase_clean | 11 |
| state | 52 |
| region | 9 |
| entity | 57 |
| service | 4 |
| project_type | 4 |
| type_1 | 14 |
| type_2 | 10 |
| type_3 | 4 |
| type_clean | 49 |

`q_status` breakdown: withdrawn 24,221; active 8,513; operational 4,789;
suspended 668; unknown 10.

`region` breakdown: West 8,097; PJM 7,666; MISO 5,424; Southeast 4,334;
**ERCOT 3,757**; CAISO 2,868; SPP 2,837; NYISO 1,936; ISO-NE 1,282.

`state` includes **non-U.S.** codes: `MB` (Manitoba), `ON` (Ontario), `MX`
(Mexico) — worth noting since the field name implies "U.S. state" but the
data isn't exclusively that. **[NEEDS VERIFICATION]** whether these
represent legitimate cross-border interconnection requests or a data-entry
category that should be excluded/handled specially — not addressed in the
codebook.

### `fips_code` — leading-zero truncation

Sample raw values: `4005, 4017, 4027, 4013, 35045, 4025, ...`. These are
stored as `float64`, so 5-digit FIPS codes for states with a single-digit
prefix (01–09) lose their leading zero (e.g. `4005` should be `04005` for
Coconino County, AZ). **Must be zero-padded to 5 digits as text before any
FIPS-based join** — otherwise it will silently fail to match standard FIPS
references (e.g. Census, EIA county data).

### Status/date logical inconsistencies

| Check | Count |
|---|---:|
| `q_status == 'withdrawn'` but `wd_date` is null | 8,639 |
| `q_status == 'operational'` but `on_date` is null | 1,500 |
| `q_status == 'active'` but `on_date` is **not** null | 158 |
| `q_status == 'withdrawn'` but `on_date` is **not** null | 257 |

**[NEEDS VERIFICATION]** — none of these are explained in the codebook.
Flagging rather than assuming they're errors; could reflect legitimate
timing/reporting gaps in the underlying queue data (e.g. a status updated
before the corresponding date field was backfilled).

### `region=='ERCOT'` vs. `state=='TX'` — not interchangeable

- `region=='ERCOT'`: 3,757 rows. `state=='TX'`: 3,442 rows.
- 539 rows have `state=='TX'` but `region` is `SPP` (420), `MISO` (100), or
  `West` (19) — this is a **real geographic fact**: parts of Texas (the
  Panhandle, El Paso area, and some eastern edges) sit outside ERCOT's
  footprint and are served by other grid operators. Not a data error.
- 854 rows have `region=='ERCOT'` with a `state` value other than `TX` —
  but on inspection, **all 854 of these actually have `state` missing**,
  not a genuinely different state. So this direction is a missingness
  artifact, not a real cross-boundary case.

### `mw_1` capacity field

Count 38,201 (0 missing). Mean 179.1 MW, std 256.6, min **-75** MW, 25th
pctile 30.2, median 100, 75th pctile 203, max 16,875 MW. **18 rows have
`mw_1 <= 0`**, including negative values — physically implausible for a
capacity field. **[NEEDS VERIFICATION]** against source queue filings;
could be data-entry sign errors or a specific convention (e.g. capacity
reduction/derate requests) not documented in the codebook.

---

## Analytical Implications

1. Any supply-side (queue) filter to "Texas" must use `region == 'ERCOT'`,
   **not** `state == 'TX'`. Using `state` would incorrectly include ~539
   non-ERCOT Texas interconnection requests (Panhandle/El Paso/other-ISO
   territory) and mishandle the 854 ERCOT rows with missing state values.
2. Any capacity aggregation from the queue data needs explicit decisions
   on: how to treat `mw_2`/`mw_3` (hybrid/co-located components), the 18
   rows with `mw_1 <= 0`, and the 270 rows in `(q_id, entity)` collision
   groups — none of which should be resolved silently during cleaning
   (per `CLAUDE.md`'s "never silently drop records" guardrail, every
   exclusion needs a documented reason).
3. `fips_code` needs zero-padding to 5 digits (as text) before it can be
   used for any county-level join to the secondary context sources
   (EIA, NREL SLOPE, DSIRE).
