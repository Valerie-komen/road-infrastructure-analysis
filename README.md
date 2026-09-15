# Kenya Road Infrastructure — Data Cleaning & Analysis

**Tooling:** Google BigQuery (SQL only) · Dataset: `light-trail-507513-q5.road_infrastructure`

A ministry road-building program tracked across three source systems — project
records, contractor progress reports, and finance disbursements — each with
its own data-entry conventions. This project cleans and reconciles all three,
then answers the business questions a ministry oversight team would actually
ask: where is the money, is it on schedule, and does spending match budget.

## What was in the dataset

| Table | Rows | State on arrival |
|---|---|---|
| `ministry_projects_raw` | 665 | Raw, all-STRING |
| `ministry_projects_clean` | 665 | Partially cleaned already (pre-existing) |
| `contractor_reports_raw` | 1,163 | Raw, all-STRING |
| `finance_disbursements_raw` | 1,648 | Raw, all-STRING |
| `county_reference` | 47 | Clean lookup (Kenya's 47 counties) |

## Data quality issues found and fixed

**County names** — 158 distinct spellings in the raw data for 47 real
counties: casing variants (`SIAYA` / `Siaya` / `siaya`), a `" County"`
suffix on some rows, and two misspellings (`Monbasa`, `Kissumu`). The
pre-existing `ministry_projects_clean` table had already normalized this
correctly — verified by joining against `county_reference` (47/47 matched,
0 unmatched) rather than re-trusting it blindly.

**A latent bug in the pre-existing "clean" budget column** — this is the
most consequential find. Any raw budget formatted `"Ksh.4,359,000,000"`
had been parsed as `0.4359` instead of 4.359 billion: the period after
`"Ksh"` was read as a decimal point. It affected 68 of 695 rows (~10%) and
understated the national budget total by roughly **112 billion KES**. Fixed
by stripping the `"Ksh."` / `"KES"` prefix as a whole token *before*
removing punctuation, so its period is never mistaken for a decimal.

**Duplicate rows** — 15 exact-duplicate `project_id` rows in the existing
"clean" table (never de-duplicated), plus a subtler issue: `ministry_
projects_raw` itself contains duplicate `project_id` rows, which caused a
silent fan-out (652 rows instead of 650) the first time the budget fix was
joined back to raw. Fixed by de-duplicating both sides before joining.

**Inconsistent project codes** — `contractor_reports_raw.project_code` and
`finance_disbursements_raw.project_ref` used at least five different
formats for the same code (`RD-2022-0364`, `RD20220185`, `RD - 2023 - 0625`,
`RD-23-0355`, `0193/2024`). Normalized all of them to the canonical
`RD-YYYY-NNNN` format used by the projects table — 0 unmatched codes in the
cleaned output (out of 1,163 contractor reports and 1,648 disbursements).

**Mixed date formats** — five formats in use across the raw date columns
(`2024-04-04`, `07-Dec-2024`, `29 July 2024`, `13/06/2022`, `07/14/2026`).
Parsed with a fallback chain that tries `DD/MM` before `MM/DD` (Kenya's
convention), letting each row's validity — not a guess — decide the format.

**Currency formatting** — budgets and disbursements arrived as plain
numbers, `"KES 1,218,000,000"`, `"Ksh.1,093,097,585"`, and
`"725000000.00"`. Normalized to `NUMERIC`.

**Left as flagged anomalies, not silently altered:**
- `completion_pct` ranges 0–127 (127 is invalid); analysis queries cap it
  at 100 with `LEAST()` rather than deleting the row.
- `tranche_number` includes a `"99"` sentinel value with no documented
  meaning — worth asking the source system owner about.
- 22 projects have disbursement records entered under **two different
  spellings** of their project code (see finding below) — reconciled for
  analysis by code, but not blended into a single "correct" amount, since
  that would be guessing rather than cleaning.

All cleaning is additive: raw tables were never modified, and each output
is a new table (`ministry_projects_v2`, `contractor_reports_clean`,
`finance_disbursements_clean`) so the source data stays available for
audit. Full SQL in [`sql/`](sql/).

## Key findings

### 1. 40% of the portfolio is behind schedule
Of 226 "Ongoing" projects, **197 (87%)** are already past their planned
completion date. Of 72 projects still "Awarded (Not Started)", **64 (89%)**
are past that same deadline without having broken ground. That's 261 of
650 projects — 40% of the entire portfolio — behind schedule.

### 2. 102 stalled projects are holding 233.2bn KES
15.7% of all projects (102 of 650) are marked "Stalled", representing
233.2bn KES in committed budget with no active progress.

| Status | Projects | Budget (bn KES) |
|---|---|---|
| Ongoing | 226 | 495.7 |
| Completed | 172 | 403.7 |
| Stalled | 102 | 233.2 |
| Awarded (Not Started) | 72 | 173.1 |
| Under Procurement | 78 | 167.1 |

### 3. National disbursement is 96.1% of budget — close to on-target
Total budget: **1,472.7bn KES**. Total disbursed: **1,415.83bn KES**
(96.1%). This looks healthy at the top line, but two sub-groups pull in
opposite directions (see next two findings).

### 4. 22 projects show apparent over-disbursement — and it's a data
### issue, not overspending
22 projects appear disbursed at ~155.6% of budget on average. Investigating
why: **every one of these 22 projects has disbursement records filed under
two different spellings of its project code** (e.g. `RD-2021-0415` and
`RD - 2021 - 0415`), each with its own tranche entries. The other 628
projects, which have disbursements under one consistent code, average a
much more plausible 90.3% disbursed. This is a duplicate-entry pattern
from the finance system, not evidence of real financial overrun —
**recommend the ministry finance team reconcile these 22 specific project
codes against source records** before treating them as a spending red
flag.

### 5. 46 projects are under-disbursed relative to budget
46 projects have received less than 50% of their allocated budget in
disbursements — worth cross-checking against the stalled-project list to
see whether funding gaps are a cause or a consequence of stalling.

### 6. Contractor performance varies sharply at similar contract value
| Contractor | Projects | Value (bn KES) | Stalled | Avg completion % |
|---|---|---|---|---|
| Cabra International | 38 | 88.3 | 6 | 39.6% |
| China Wu Yi Co Ltd | 33 | 88.2 | 5 | 42.9% |
| Reynolds Construction | 32 | 75.1 | **8** | 51.4% |
| Spencon Services | 28 | 62.7 | 5 | **60.9%** |
| China Overseas Engineering | 24 | 53.2 | 3 | **33.6%** |

Reynolds Construction carries the highest stall count (8 of 32 projects,
25%) among top contractors by value. China Overseas Engineering has the
lowest average completion rate (33.6%) despite a similar project count to
peers. Spencon Services stands out with the best completion rate (60.9%)
among the top 12 contractors by value — a useful benchmark when awarding
future contracts.

### 7. Bomet leads county-level capital commitment
Bomet county has the highest total committed budget (54.75bn KES across 21
projects), followed by Siaya (53.44bn/25), Nyeri (46.16bn/20), Machakos
(45.83bn/14), and Isiolo (45.63bn/20). Machakos stands out for concentrating
similar capital (45.83bn) into fewer projects (14) than its peers — larger
average project size worth understanding (bridge vs. road-length mix).

## Recommendations

1. **Audit the 22 duplicate-code projects** in finance before reporting
   national disbursement figures externally — the true rate is closer to
   90% than the blended 96–104% depending on how duplicates are handled.
2. **Investigate the 102 stalled projects** (233.2bn KES) as a priority —
   this is the single largest pool of committed-but-idle capital.
3. **Review Reynolds Construction and China Overseas Engineering** against
   their contract terms given below-average completion and above-average
   stall rates at meaningful contract value.
4. **Clarify the `tranche_number = 99`** convention with the finance
   system owner — it's outside the normal 1–4 range and its meaning is
   undocumented.
5. **Standardize project-code entry** at the point of data entry (one
   canonical format) to prevent the duplicate-spelling issue from
   recurring in future disbursement records.

## Files

- [`sql/01_data_profiling.sql`](sql/01_data_profiling.sql) — diagnostic
  queries used to find every issue listed above
- [`sql/02_cleaning.sql`](sql/02_cleaning.sql) — the cleaning pipeline,
  fully commented with the reasoning behind each transformation
- [`sql/03_analysis_queries.sql`](sql/03_analysis_queries.sql) — the
  business-question queries behind every finding in this report
