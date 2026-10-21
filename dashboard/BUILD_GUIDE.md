# Power BI Dashboard — Build Guide

Companion to [`mockup.html`](mockup.html) (open it in a browser — that's the exact
layout and colors to build toward) and [`power_bi_theme.json`](power_bi_theme.json)
(import it directly into Power BI so every visual picks up the right colors
automatically).

## 1. Load the data

The four cleaned tables are already exported to [`../data/`](../data/) as
CSVs (pulled straight from the BigQuery tables built in `sql/02_cleaning.sql`,
so they match exactly what the analysis is based on) — this is the easiest
path and needs no BigQuery sign-in inside Power BI at all:

1. Power BI Desktop → **Get Data** → **Text/CSV**.
2. Select `data/ministry_projects_v2.csv` → **Load**. Repeat for
   `data/contractor_reports_clean.csv`, `data/finance_disbursements_clean.csv`,
   and `data/county_reference.csv` — four separate imports.
3. In Power Query (**Transform Data** before the final load, or **Transform
   Data** again afterward from Home), confirm: `budget_kes` / `amount_kes`
   are **Decimal Number**, `start_date` / `planned_completion_date` /
   `report_date` / `disbursement_date` are **Date**, `completion_pct` is
   **Decimal Number**. CSV import sometimes guesses text for these — fix
   any that came in wrong via the column header's type icon.
4. **Home → Close & Apply.**

*(If you'd rather connect live to BigQuery instead — e.g. to show a
recruiter the pipeline update automatically — use Get Data → Google
BigQuery, sign in with `valeriekomen@gmail.com`, and pick the same four
tables under `light-trail-507513-q5.road_infrastructure`. The CSVs are the
faster path to a finished dashboard; the live connection is a nice option
to mention in an interview but not necessary to build the file.)*

## 2. Build the data model

Go to the **Model** view (left rail, third icon) and draw these relationships
by dragging `project_id` between tables:

| From | To | Cardinality |
|---|---|---|
| `ministry_projects_v2[project_id]` | `contractor_reports_clean[project_id]` | 1 → many |
| `ministry_projects_v2[project_id]` | `finance_disbursements_clean[project_id]` | 1 → many |
| `ministry_projects_v2[county]` | `county_reference[county_name]` | many → 1 |

`ministry_projects_v2` is your fact table's anchor — everything else hangs
off it. This is a simple star schema, which is exactly what a recruiter
skimming your model view wants to see (not one flat denormalized table).

## 3. Import the color theme

**View → Themes → Browse for themes...** → select `power_bi_theme.json`.
Every new visual will now default to the right palette — you shouldn't need
to hand-pick colors except where the guide below calls out a specific status
color per category.

## 4. Create the DAX measures

New table or Home → **New Measure**, one at a time, in a measures table
(Modeling → New Table → name it `_Measures` so they're easy to find):

```dax
Total Projects = DISTINCTCOUNT(ministry_projects_v2[project_id])

Total Budget (bn) = SUM(ministry_projects_v2[budget_kes]) / 1000000000

Total Disbursed (bn) =
DIVIDE(SUM(finance_disbursements_clean[amount_kes]), 1000000000)

Pct Disbursed =
DIVIDE([Total Disbursed (bn)], [Total Budget (bn)])

Stalled Projects =
CALCULATE([Total Projects], ministry_projects_v2[status] = "Stalled")

Overdue Projects =
CALCULATE(
    [Total Projects],
    ministry_projects_v2[status] IN {"Ongoing", "Awarded (Not Started)"},
    ministry_projects_v2[planned_completion_date] < TODAY()
)

Pct Overdue = DIVIDE([Overdue Projects], [Total Projects])

Avg Completion Pct =
AVERAGEX(
    FILTER(contractor_reports_clean, contractor_reports_clean[completion_pct] >= 0),
    MIN(contractor_reports_clean[completion_pct], 100)
)
```

## 5. Lay out the page

Set the page size first: **View → Page view → Actual size**, then in the
Format pane (with nothing selected) set **Canvas settings → Type → Custom**,
1280 × 800px, matching the mockup's proportions.

Build top to bottom, left to right — this order matters, it's the order a
recruiter's eye will travel:

### Row 1 — Title
A text box, not a visual: **"Kenya Road Infrastructure — Portfolio
Oversight"** at 22pt Segoe UI Semibold, with a smaller subtitle line
underneath at 12pt in the muted gray (`#52514e`): *"650 projects · KES
1,472.7B committed · cleaned & modeled from BigQuery SQL"*.

### Row 2 — KPI cards (5 across)
Five **Card** visuals in a row, equal width, thin border, radius 4 (the
theme JSON sets this automatically). Fields:
1. `[Total Projects]`
2. `[Total Budget (bn)]` — format as `"KES "#,##0.0"B"` in the measure's
   Format pane
3. `[Total Disbursed (bn)]` — same custom format
4. `[Overdue Projects]` — set this card's data color to `#d03b3b`
   (critical red) under Format → Callout value
5. `[Stalled Projects]` — same critical red; this is the one card that
   should visually jump out

### Row 3 — three panels
- **Left (40% width): Clustered bar chart** — Axis: `status`, Values:
  `[Total Budget (bn)]`. Under Format → Data colors, set each status
  manually to match the mockup's semantic mapping (this is the one place
  the theme's default categorical order won't match — status needs
  deliberate mapping, not automatic assignment):
  - Ongoing → `#2a78d6` (blue)
  - Completed → `#0ca30c` (good/green)
  - Under Procurement → `#fab219` (warning/amber)
  - Awarded (Not Started) → `#ec835a` (serious/orange)
  - Stalled → `#d03b3b` (critical/red)
- **Middle (25%): Donut chart** — a single category with two values (Overdue
  vs. On Track) using `[Overdue Projects]` and `[Total Projects] -
  [Overdue Projects]`. Color the Overdue slice critical red, On Track a
  neutral gray. Add a **Card** visual centered on top showing `[Pct
  Overdue]` at 30pt — Power BI doesn't support true overlaid center text on
  a donut, so this is a card placed visually on top of the donut, both
  grouped together.
- **Right (35%): Horizontal bar chart** — Axis: `county` (Top N filter: top
  10 by budget), Values: `[Total Budget (bn)]`. Use the sequential blue
  ramp: right-click the visual → Format → Data colors → **Conditional
  formatting** → gradient from `#cde2fb` (low) to `#0d366b` (high) — this
  reads as "more blue = more capital," which is the correct sequential
  encoding for a magnitude comparison.

### Row 4 — two panels
- **Left (60%): Scatter chart** — X: `[Avg Completion Pct]`, Y:
  `CALCULATE([Total Projects], status="Stalled")` per contractor, Size:
  `[Total Budget (bn)]`, Legend: `contractor` (filter to top 10-12 by
  budget first, via a Top N filter, so the legend doesn't sprawl — more
  than ~8 bubbles gets unreadable). Turn on **data labels** for just the
  two or three contractors worth calling out (best completion rate, most
  stalls) rather than labeling every bubble.
- **Right (40%): a Text box, not a chart.** This is the differentiator most
  student dashboards skip — three short callouts in plain text describing
  the data-quality issues you found (the Ksh. parsing bug, the duplicate
  project-code disbursements, the county-spelling cleanup). A recruiter who
  reads this understands you did real analytical work, not just
  drag-and-drop charting. Keep each to 1–2 sentences. See `mockup.html`
  for exact wording you can reuse or adapt.

### Footer
A thin text line: *"Source: BigQuery · SQL in road-infrastructure-analysis
repo · Built by Valerie Komen"* — and if you're publishing this to Power BI
Service, this is also where a link to your GitHub repo belongs.

## 6. Make it interactive: add slicers

Power BI cross-filters automatically when you click any bar, slice, or
bubble — but a recruiter should also see obvious controls to play with,
not just discover clicking by accident. Add a thin filter strip directly
under the title (between Row 1 and Row 2):

- **County slicer** — Field: `county`. Format as a dropdown (Format →
  Slicer settings → Style → Dropdown) rather than a list, so it stays
  compact in the strip.
- **Status slicer** — Field: `status`. Use the "Tile" style with the same
  five status colors from the bar chart, so it doubles as a legend.
- **Contractor slicer** — Field: `contractor`, dropdown style.

Set all three to **single-select off** (Format → Selection controls) so
someone can multi-select. Sync them across pages if you add the
drill-through page below (Format → Edit interactions, or the Sync slicers
pane).

## 7. Add a drill-through page for flagged projects

This is the piece that answers "does it cover everything the analysis
found" — right now the 22 over-disbursed and 46 under-disbursed projects
only exist as a number and a text callout. Give them a page of their own:

1. **Insert → New page**, name it "Flagged Projects."
2. Add a **Table** visual with columns: `project_id`, `project_name`,
   `county`, `contractor`, `status`, and two new measures:
   ```dax
   Disbursed (bn) =
   DIVIDE(SUM(finance_disbursements_clean[amount_kes]), 1000000000)

   Pct of Budget Disbursed =
   DIVIDE([Disbursed (bn)], [Total Budget (bn)])
   ```
3. Add a **Filter** on the visual: `Pct of Budget Disbursed` is greater
   than 1.05 **or** less than 0.5 — this reproduces the audit list from
   `sql/03_analysis_queries.sql` section E directly in the report.
4. Conditionally format `Pct of Budget Disbursed`: red text above 105%,
   amber below 50%, using Format → Conditional formatting → Font color →
   Rules.
5. Back on the main page, make the "Behind Schedule" and "Stalled
   Projects" KPI cards **drill-through targets**: right-click each →
   nothing needed on this end, just add both fields (`status`,
   `Pct of Budget Disbursed`) to the **Drill through** filter well on the
   Flagged Projects page (Format pane → Drill through section). Now a
   recruiter can click "102" on the Stalled card and land straight on the
   filtered detail table — that click-through is what makes a dashboard
   feel like a real tool instead of a static image.

## 8. Final polish pass (do this last, all at once)

- **Align everything to a grid.** Select all visuals → Format → **Align →
  Distribute horizontally/vertically**. Nothing should be a pixel off from
  its neighbor — this is the single biggest "looks professional vs. looks
  like a first draft" factor.
- **Turn off visual headers** (the little icon strip that appears on
  hover) for the final export — Format → General → Header icons → off —
  they're a Power BI editing affordance, not part of the design.
- **Remove default titles you didn't write.** Power BI auto-titles a
  visual "Sum of budget_kes by status" — replace every one with the short,
  human title already shown in the mockup panels.
- **Check color contrast at a glance:** squint at the page or view it at
  50% zoom — the five KPI cards and the status colors should still read
  clearly. If anything blends together, that's the cue to add a border or
  bump contrast, not to add more color.
- **Export a static image or PDF** of the finished page (File → Export →
  PDF, or a screenshot) to embed in your GitHub README and LinkedIn post —
  most recruiters will see a screenshot before they ever open the live
  file.

## Where this fits in your portfolio

Link this dashboard from your `README.md` alongside the SQL work, something
like: *"See the [Power BI dashboard](link) built on top of this cleaned
dataset."* A recruiter who sees BigQuery SQL **and** a polished Power BI
dashboard **and** a written data-quality narrative from the same project is
seeing the full analyst skill set in one place — that's the actual goal
here, not the dashboard in isolation.
