# Tableau Build Steps

Literal, click-by-click steps for building the three dashboards specified
in `tableau/dashboard_design.md` (field meanings: `tableau/README.md`).
Written for Tableau Desktop; the same steps work in Tableau Public with
minor menu differences.

**One correction made while writing this walkthrough:** the "Drivers of
Risk" component-breakdown chart's scenario selector can't actually work
from `tableau_final.csv` alone — that file only carries the base_case
scenario's weights. It needs `output/analysis/risk_score_sensitivity.csv`
(which has weights *and* scores for all 3 scenarios) instead. This is
already fixed in `tableau/dashboard_design.md`; the steps below build the
corrected version.

---

## Part A — Connect to data (once)

1. Open Tableau Desktop → **Connect → Text File** → select
   `data/processed/tableau_final.csv`.
2. On the Data Source page, double-click the data source name at the top
   and rename it **"Snapshot."**
3. **Data menu → New Data Source → Text File** → select
   `output/analysis/risk_score_sensitivity.csv`. Rename it
   **"Sensitivity."**
4. Leave these as two separate, unrelated connections — don't join or
   blend them. No single worksheet below needs fields from both at once.

---

## Part B — Shared calculated fields & parameters (build once)

All of these go on the **Snapshot** data source unless noted.

**1. Guardrail Caption** (Analysis → Create Calculated Field):
```
"Interconnection queue MW is potential future capacity currently in the
queue — not deliverable or guaranteed MW. The Procurement Risk Score is
an analytical construct reflecting a specific weighting scheme, not
objective truth."
```

**2. Snapshot Label:**
```
"ERCOT snapshot as of " + STR([As Of Date])
```

**3. Delivery Gap Label:**
```
IF [Delivery Gap Mw] < 0 THEN
    "Total queue capacity exceeds demand by " + STR(ROUND(ABS([Delivery Gap Mw]),0)) + " MW"
ELSE
    "Demand exceeds total queue capacity by " + STR(ROUND([Delivery Gap Mw],0)) + " MW"
END
```

**4. "Color By" parameter** (right-click in the Data pane → Create
Parameter): Data type **String**; Allowable values **List**: "Procurement
Risk Score", "Demand Pressure Ratio", "Queue Attrition Rate"; current
value "Procurement Risk Score."

**5. Selected Color Measure** (calculated field, uses the parameter):
```
CASE [Color By]
WHEN "Procurement Risk Score" THEN [Procurement Risk Score]
WHEN "Demand Pressure Ratio" THEN [Demand Pressure Ratio]
WHEN "Queue Attrition Rate" THEN [Queue Attrition Rate]
END
```

**Note on field names:** the CSV headers are snake_case
(`as_of_date`, `delivery_gap_mw`, etc.) but Tableau auto-displays them in
Title Case in the Data pane and in formulas (`[As Of Date]`,
`[Delivery Gap Mw]`) — that's expected, not a typo.

---

## Part C — The "big number" KPI tile (recipe, used ~11 times)

Every KPI tile across all three dashboards is the same recipe:

1. New worksheet.
2. Drag the measure onto **Text** on the Marks card (mark type: Text).
3. Click the Text mark → increase font size substantially (32–48 pt),
   center it.
4. Right-click the field (in the Data pane, or on the Marks card) →
   **Default Properties → Number Format** → set: MW fields = Number
   (Custom), thousands separator, 0 decimals; ratios
   (`demand_pressure_ratio`, `queue_attrition_rate`) = 2 decimals (or
   Percentage for the attrition rate); scores = 1 decimal.
5. Double-click the worksheet title and replace it with a short caption
   (e.g. "Corporate Demand (MW)") — or leave the title blank and instead
   place a small text object with the caption above the tile once it's
   on the dashboard, if you want consistent caption styling across tiles.
6. Right-click the view → uncheck any visible headers/gridlines you don't
   want (a KPI tile should show just the number and its caption).

Repeat for every tile listed under each dashboard below.

---

## Part D — Dashboard 1: Executive Overview

**Data source: Snapshot**, except where noted.

### D1. KPI tiles (×4, Part C recipe)
Corporate Demand (`corporate_demand_mw`) · Total Queue Capacity
(`total_queue_mw`) · Delivery Gap (use **Delivery Gap Label** on Text
instead of the raw number, so the sign-aware phrasing shows) ·
Procurement Risk Score (`procurement_risk_score`).

### D2. Demand vs. Supply Comparison (bar chart)
1. New worksheet, rename "Demand vs Supply."
2. Drag **Measure Names** to Columns, **Measure Values** to Rows.
3. Drag **Measure Names** to Filters → check only `corporate_demand_mw`
   and `total_queue_mw` (uncheck everything else).
4. Right-click each value on the Columns shelf pill/legend → **Aliases**
   → rename `corporate_demand_mw` → "Corporate Demand,"
   `total_queue_mw` → "Total Queue Capacity."
5. Manually reorder so Demand appears before Total Queue Capacity (drag
   the pill order on the Columns shelf, or set a manual sort).
6. Format the Measure Values axis: title "MW," thousands separator, 0
   decimals.
7. Add a worksheet subtitle/caption text: "Total queue capacity currently
   exceeds corporate demand at this snapshot — see the Regional Risk
   dashboard for the map, Drivers of Risk for what's behind the
   composite score." (Edit the direction if the numbers ever flip.)

### D3. Score + Sensitivity Strip (small chart)
1. New worksheet, rename "Score + Sensitivity Strip."
2. Drag **Measure Names** to Columns, **Measure Values** to Rows.
3. Filter Measure Names to exactly: `procurement_risk_score`,
   `sensitivity_score_demand_pressure_heavy`,
   `sensitivity_score_queue_risk_heavy`.
4. Alias: `procurement_risk_score` → "Base Case,"
   `sensitivity_score_demand_pressure_heavy` → "Demand-Pressure-Heavy,"
   `sensitivity_score_queue_risk_heavy` → "Queue-Risk-Heavy."
5. Change the mark type to Circle (Marks card dropdown) and add value
   labels — keep this visually compact; it's a supporting strip, not the
   dashboard's main chart.
6. Caption: "Composite score under 3 different, equally defensible
   weighting choices. Full breakdown: Drivers of Risk dashboard."

### D4. Assemble the dashboard
1. **Dashboard → New Dashboard**, name "Executive Overview," size Fixed
   1200×900 (or your preferred fixed size).
2. Add a Text object at the top: title "Corporate Electricity Demand vs.
   Grid Interconnection Capacity — ERCOT Snapshot," subtitle using the
   **Snapshot Label** calculated field plus the guardrail sentence (you
   can type the guardrail text directly, or place a tiny worksheet
   showing **Guardrail Caption** on Text and float it here).
3. Add a small Text object noting: "This snapshot has no filterable
   dimensions — one region, one point in time."
4. Drag the 4 KPI tiles into a horizontal container below the header.
5. Drag "Demand vs Supply" below the KPI row, full width.
6. Drag "Score + Sensitivity Strip" below that.
7. Add a footer Text object with the guardrail caption repeated.

---

## Part E — Dashboard 2: Regional Risk

**Data source: Snapshot.**

### E1. Regional KPI tiles (×5, Part C recipe)
Corporate Demand (`corporate_demand_mw`) · Active Queue Capacity
(`active_queue_mw`) · Withdrawn Queue Capacity (`withdrawn_queue_mw`) ·
Queue Attrition Rate (`queue_attrition_rate`) · Queue Age
(`queue_age_days`, with a small secondary caption showing
`n_active_projects_for_queue_age` as "based on N active projects").

### E2. ERCOT/Texas Map
1. New worksheet, rename "ERCOT Map."
2. Drag `State For Map` onto the view. Tableau should recognize "Texas"
   automatically via the State/Province geographic role. If it shows a
   warning icon instead, right-click the field in the Data pane →
   **Geographic Role → State/Province.**
3. From **Show Me**, pick "Filled Maps" (or set the Marks card mark type
   to "Map").
4. Drag **Selected Color Measure** (built in Part B) onto **Color** on
   the Marks card.
5. Confirm the legend renders as a **continuous** gradient, not a
   stepped/binned legend (right-click the legend → make sure "Edit
   Colors" shows a continuous ramp, not manually-defined discrete steps).
   This matters: never bucket the score into discrete tiers (see
   `tableau/dashboard_design.md`'s constraint section for why).
6. Right-click the **Color By** parameter (bottom of the Data pane, under
   Parameters) → **Show Parameter Control** — this adds the dropdown that
   lets a viewer swap what the map colors by.
7. Build the Tooltip: drag `corporate_demand_mw`, `active_queue_mw`,
   `withdrawn_queue_mw`, `queue_attrition_rate`, `queue_age_days`, and
   **Guardrail Caption** onto Tooltip on the Marks card; edit the tooltip
   text layout for readability.

### E3. Assemble the dashboard
1. New Dashboard, "Regional Risk," same fixed size.
2. Header Text object: title "ERCOT Regional Risk Profile," subtitle —
   put the scope statement **first, above everything else**: "This
   analysis covers ERCOT (Texas) only — the single U.S. grid region
   measured in this dataset. No cross-region comparison is available.
   The map below approximates ERCOT's footprint using the Texas state
   boundary — see `tableau/README.md`'s Map caveat."
3. Drag the "ERCOT Map" worksheet in as the primary element.
4. Drag the 5 regional KPI tiles into a panel beside or below the map.
5. Make sure the Color By parameter control (from E2 step 6) is visible
   on this dashboard, not just the worksheet.
6. Footer Text object with the guardrail caption.

---

## Part F — Dashboard 3: Drivers of Risk

**Data source: Sensitivity** for both charts below;
**Snapshot** for the KPI tiles.

### F1. KPI tiles (×3, Part C recipe, Snapshot data source)
Procurement Risk Score (`procurement_risk_score`) · Queue Attrition Rate
normalized (`norm_queue_attrition`) · Queue Age
(`queue_age_days`).

### F2. Weighted Contribution calculated field (on Sensitivity)
```
CASE [Measure Names]
WHEN "Norm Demand Pressure" THEN [Norm Demand Pressure] * [Weight Demand Pressure]
WHEN "Norm Delivery Gap" THEN [Norm Delivery Gap] * [Weight Delivery Gap]
WHEN "Norm Queue Attrition" THEN [Norm Queue Attrition] * [Weight Queue Attrition]
WHEN "Norm Queue Age" THEN [Norm Queue Age] * [Weight Queue Age]
END
```
This one calculated field works for all four components because it
reads whichever measure is currently on the view via `[Measure Names]` —
no need for four separate contribution fields.

### F3. Component Breakdown (bar chart, with scenario selector)
1. New worksheet, rename "Component Breakdown," data source Sensitivity.
2. Drag **Measure Names** to Columns, **Measure Values** to Rows.
3. Filter Measure Names to exactly: `norm_demand_pressure`,
   `norm_delivery_gap`, `norm_queue_attrition`, `norm_queue_age`.
4. Alias each: → "Demand Pressure," "Delivery Gap," "Queue Attrition,"
   "Queue Age."
5. Drag **Weighted Contribution** (Part F2) onto **Label** on the Marks
   card, alongside the bar's raw value — e.g. show both "32.0" (the bar)
   and "contributes 10.7" (the label).
6. Drag `Scenario` to Filters → in the filter dialog select
   **"base_case"** as the default. Right-click the filter card →
   **Show Filter** → set the control style to "Single Value (dropdown)"
   → rename the control's displayed values via Aliases: "base_case" →
   "Base Case," "demand_pressure_heavy" → "Demand-Pressure-Heavy (60/40),"
   "queue_risk_heavy" → "Queue-Risk-Heavy (20/80)."
7. **Important:** right-click the Scenario filter card → **Apply to
   Worksheets → Only this worksheet.** If you leave it on "All Using
   This Data Source," it will also filter the Sensitivity Range chart
   built next, which needs to show all 3 scenarios at once.
8. Add a caption: "Bar heights don't change with the selected scenario —
   `norm_*` values are identical across all 3 weightings. Only how much
   each component counts toward the composite score changes — see the
   Weighted Contribution label."

### F4. Sensitivity Range / Tornado Chart
1. New worksheet, rename "Sensitivity Range," data source Sensitivity —
   **no scenario filter on this one.**
2. Drag `Scenario` to Rows, `Procurement Risk Score` to Columns.
3. Alias scenario values: "Base Case," "Demand-Pressure-Heavy (60/40),"
   "Queue-Risk-Heavy (20/80)" (same aliases as F3, for consistency).
4. Sort rows in that fixed order (drag manually, or set a manual sort on
   the Scenario field).
5. Drag `Primary Driver` onto Label; drag `Score Vs Base` onto Tooltip.
6. Optional: **Analytics pane → Reference Line** → add a reference line
   at the base_case value, so the two alternative scenarios visually
   read as deviations from it (a simple range/dumbbell effect without
   needing a custom dual-axis chart).

### F5. Assemble the dashboard
1. New Dashboard, "Drivers of Risk," same fixed size.
2. Header Text object: title "What's Driving the Procurement Risk
   Score," subtitle: "Four weighted components combine into the
   composite score below. This score reflects a chosen weighting scheme,
   not an objective ranking — the scenarios further down show how much
   it moves under two other equally defensible weightings. Normalization
   thresholds for three of the four components are provisional
   placeholders, not empirically calibrated."
3. Drag the 3 KPI tiles into a row.
4. Drag "Component Breakdown" below the KPI row (make sure its Scenario
   filter control is visible on the dashboard).
5. Drag "Sensitivity Range" below that, full width.
6. Footer Text object with the fullest version of the guardrail caption
   (this dashboard is the methodology page — the extra provisional-
   thresholds caveat belongs here, not repeated on the other two).

---

## Part G — Cross-dashboard navigation

On each of the three dashboards:
1. **Dashboard menu → Show Title** (if not already shown), or add a
   floating **Navigation Object** (Objects pane → drag "Navigation" onto
   the dashboard).
2. Configure it to link to the other two dashboards (one button per
   target), labeled clearly: "Executive Overview," "Regional Risk,"
   "Drivers of Risk."
3. Place this navigation strip in the same position on all three
   dashboards (e.g., top-right) so the ~2-minute path reads as one guided
   sequence rather than three pages a viewer has to discover via tabs.

---

## Part H — Final QA checklist before calling it done

- [ ] No chart anywhere uses a discrete risk tier/bucket — the map and
      the component breakdown both use continuous color scales.
- [ ] No trend line or "over time" chart appears on any of the three
      dashboards.
- [ ] No cross-region comparison chart exists — the map shows ERCOT
      only, and Dashboard 2's subtitle says so before the map itself.
- [ ] Every dashboard's header or footer includes the "queue MW is
      potential, not guaranteed/delivered, capacity" guardrail language
      somewhere a viewer will actually read it (not only in a tooltip).
- [ ] The Procurement Risk Score never appears without its weighting
      scheme and sensitivity results visible on the same dashboard
      (Executive Overview's condensed strip; Drivers of Risk's full
      versions).
- [ ] Time yourself clicking through all three dashboards in the
      recommended order — confirm the ~2-minute target is realistic once
      built, and trim/simplify if it runs long.
