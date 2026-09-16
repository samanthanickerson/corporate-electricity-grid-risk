# Preliminary Data Dictionary

Field-by-field reference for the raw sources currently in `data/raw/`.
**Preliminary and read-only** — compiled by inspecting the raw files, not
by cleaning or transforming them. Definitions are quoted from official
source documentation where it exists; anything without a documented
source is marked **UNVERIFIED** and should be confirmed before analytical
use. See `docs/data_reconnaissance.md` for the full inspection findings
this is drawn from.

Compiled 2026-08-17.

---

## `data/raw/berkeley_lab/Queued_Up_Data.xlsx` — sheet `03. Complete Queue Data`

All 30 definitions below are quoted from the workbook's own
`04. Data Codebook` sheet (Definition source = "LBNL codebook"), not
inferred from field names.

| Field | Data type (as read) | Definition (source: LBNL codebook) | Notes/caveats |
|---|---|---|---|
| `q_id` | string | "queue position / ID number" | Codebook says combine with `entity` for a unique ID — **verified unreliable**: 135 duplicate `(q_id, entity)` pairs found (270 rows). Contains one literal `'not assigned'` value. |
| `q_status` | string | "current queue status" | One of: active, withdrawn, suspended, or operational (codebook also lists an "unknown" value observed in the data, 10 rows — not explicitly listed in the codebook's enum). |
| `q_date` | datetime | "interconnection request date (date project entered queue)" | 1.7% missing. |
| `prop_date` | datetime | "proposed online date from interconnection application" | Codebook notes: "Proposed date can be revised during the interconnection process." 13.8% missing. |
| `on_date` | datetime | "date project became operational (if applicable)" | 90.3% missing (expected — conditional on status). 1,500 `operational` rows are missing this despite the condition — **UNVERIFIED**, flagged in reconnaissance doc. |
| `wd_date` | datetime | "date project withdrawn from queue (if applicable)" | 59.1% missing. 8,639 `withdrawn` rows missing this — **UNVERIFIED**. |
| `ia_date` | datetime | "date of signed interconnection agreement (if applicable)" | 87.4% missing. |
| `IA_phase_raw` | string | "non-standardized interconnection study phase / status from queue" | 1,184 unique free-text values — not suitable for direct grouping. |
| `IA_phase_clean` | string | "standardized interconnection study phase / status" | Codebook: "We impute 'IA Executed' if q_status is 'operational'." One of: IA Executed, Withdrawn, System Impact Study, Feasibility Study, Facility Study, In Progress (unknown study), Cluster Study, IA Pending, Not Started, Construction, Suspended. |
| `county` | string | "county where project is located" | Codebook: "For requests spanning multiple counties, only the first listed county is included." 5.4% missing. |
| `state` | string | "state where project is located" | 52 unique values — includes non-U.S. codes `MB`, `ON`, `MX`. **UNVERIFIED** whether these are legitimate or a special data-entry category; field name implies U.S.-only but data isn't. 3.2% missing. |
| `fips_code` | float64 (should be 5-digit text) | "5-digit FIPS code" — codebook: "Unique, standardized numeric codes to identify counties" | Stored as float64, **drops leading zeros** for state prefixes 01–09 (e.g. `4005` instead of `04005`). Must be zero-padded before use. 4.6% missing. |
| `poi_name` | string | "point of interconnection name" | Codebook: "May be a substation name or transmission line tap." 7.4% missing. |
| `region` | string | "standardized region where project is located" | Codebook: "One of: the 7 ISOs; and West (non-ISO) or Southeast (non-ISO)." 9 unique values, 0% missing. **Not the same as `state=='TX'`** — see reconnaissance doc. |
| `project_name` | string | "project name" | Codebook: "Not available for most requests." 65.7% missing (consistent). |
| `utility` | string | "utility name" | Codebook: "Same as 'entity' in non-ISO/RTO balancing areas." 20.6% missing. |
| `entity` | string | "transmission provider entity name (ISO or utility)" | Codebook: "One of the 57 regions listed on the 01. Balancing Areas sheet." 0% missing. |
| `developer` | string | "non-standardized project developer name" | Codebook: "Not available for most requests." 77.8% missing (consistent). |
| `cluster` | string | "queue cluster (if applicable)" | No further detail in codebook. 67.6% missing. |
| `service` | string | "interconnection service type" | One of: NRIS, ERIS, NRIS/ERIS, or Other. 28.3% missing. |
| `project_type` | string | "type of project or interconnection request" | One of: Generation, Surplus, Upgrade, or Replacement. Codebook: "Not all upgrades / uprates are identified." 3.2% missing. |
| `type_1` | string | "resource type 1" | One of: Solar, Wind, Battery, Gas, Hydro, Coal, Offshore Wind, Nuclear, Geothermal, Diesel, Oil, Hydrogen, Other Storage, Other. 0% missing. |
| `type_2` | string | "resource type 2" | Codebook: "If populated, indicates hybrid / co-located project." 86.8% missing (expected). |
| `type_3` | string | "resource type 3" | Same pattern as `type_2`. 99.7% missing (expected). |
| `type_clean` | string | "resource type - standardized" | Codebook: "Combined resource types if hybrid/co-located (e.g., 'Solar+Battery')." 49 unique values (combinatorial from `type_1/2/3`). 0% missing. |
| `mw_1` | float64 | "capacity of type 1 (MW)" — codebook: "Rated electric capacity of the generation or storage plant" | 0% missing, but **18 rows have `mw_1 <= 0`** including negative values — **UNVERIFIED**, physically implausible for a capacity field as documented. |
| `mw_2` | float64 | "capacity of type 2 (MW)" | Codebook notes imputed storage capacity values for hybrids are *excluded* from this reported field where `mw_2`/`mw_3` were originally missing. 97.1% missing. |
| `mw_3` | float64 | "capacity of type 3 (MW)" | Same caveat as `mw_2`. 99.9% missing. |
| `q_year` | float64 (year) | "year project entered queue" — "Derived from q_date" | 1.7% missing (matches `q_date`). |
| `prop_year` | float64 (year) | "proposed online year from interconnection application" — "Derived from prop_date" | 13.8% missing (matches `prop_date`). |

---

## `data/raw/ercot_large_load/` — ERCOT Large Load interconnection queue (via ercotqueue.com)

**Source & license:** [ercotqueue.com](https://www.ercotqueue.com) —
**License: CC BY 4.0**
(https://creativecommons.org/licenses/by/4.0/). ercotqueue.com is an
independent third-party tracker, **not** an ercot.com property. It states
its own figures are transcribed/curated from **ERCOT's Large Load Working
Group (LLWG) "Large Load Interconnection Status Update" reports**
(published as PPTX slide decks) — the underlying primary/official ERCOT
filing. Every figure below cites the specific LLWG report and slide it
came from, per ercotqueue.com's own per-record `notes` field (preserved
verbatim in the `source_citation` column produced by
`R/01_import_clean.R`). Verified live 2026-08-17: domain resolves, both
JSON endpoints return data, license and LLWG attribution confirmed via the
site's own `/methodology` page. `robots.txt` allows `/data/load/`.

**Important caveat — aggregate, not project-level:** despite the filename
`load_projects.json`, this source does **not** provide a complete named
customer/project queue (ERCOT doesn't publicly disclose one). Both JSON
files contain **aggregate/bucketed** MW totals only — `load_projects.json`
has just 8 records, all `record_type: "aggregate"` or
`"anonymized_bucket"`, each carrying its own `confidentiality_note`
confirming this. This is structurally different from the Berkeley Lab
source, which is row-per-project.

| Field (from `load_queue_summary.json`, as parsed by `parse_load_queue_summary()`) | Data type | Definition (source) | Notes/caveats |
|---|---|---|---|
| `dimension` | string (`status_funnel` or `sector`) | Added during parsing to distinguish the two independent breakdowns the source reports | **`status` and `sector` are never reported together for the same MW figure in the source** — they're two separate cuts of the same total queue, not a joint cross-tab. Do not sum `mw` across both `dimension` values. |
| `status` | string (7 values: submitted, approved_to_energize, observed_energized, approved_to_energize_not_operational, planning_studies_approved, under_ercot_review, no_studies_submitted) | ercotqueue.com's status-funnel labels for the LLWG queue stages | Populated only when `dimension == "status_funnel"`. 3 of 7 statuses have `mw = NA` — not published in ERCOT's public LLWG summary (internal-stage figures). |
| `sector` | string (4 values: data_center, crypto, industrial, other) | ercotqueue.com's resource-sector classification, per LLWG report slide 14 ("Large Load Project Distribution by Type") | Populated only when `dimension == "sector"`. "other" is a residual computed by ercotqueue.com (total minus the three named sectors), not a directly labeled ERCOT category. |
| `mw` | numeric | Megawatts for the given status or sector bucket, as reported/derived from the cited LLWG report slide | As of the June 2026 snapshot: total queue 466,497 MW. **Queue MW is not deliverable MW** — same guardrail as the Berkeley Lab generation queue data. |
| `project_count` | integer | Number of projects in the bucket | **Always NA in the current snapshot** — ERCOT's public LLWG summary reports MW totals but not project counts per bucket. |
| `as_of_date` | date | Snapshot date the figures apply to (`summary$as_of_date` in the source JSON) | 2026-06-18 in the snapshot inspected 2026-08-17. This is a point-in-time snapshot, not a live feed — re-fetch to update. |
| `source_citation` | string | Constructed in `parse_load_queue_summary()`: a fixed CC BY 4.0/ercotqueue.com/LLWG attribution prefix + the source's own per-record `notes` text verbatim | The `notes` text itself is ercotqueue.com's citation (report date, slide number, sometimes a direct quote) — treat as their claim about the primary source, not independently verified against the LLWG PPTX by this project. |

**[NEEDS VERIFICATION]** The LLWG PPTX reports themselves have not been
independently retrieved/checked by this project — the citations above are
ercotqueue.com's own attribution, which appeared credible and specific
(slide-level, with discrepancies like the 8,927 vs. 8,926 MW figure
explicitly disclosed rather than silently resolved) but has not been
cross-checked against ERCOT's original filing.
