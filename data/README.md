# Cleaned data snapshots

CSV exports of the four analysis-ready tables built by
[`sql/02_cleaning.sql`](../sql/02_cleaning.sql), pulled directly from
BigQuery so the row counts match the analysis exactly:

| File | Rows | Source table |
|---|---|---|
| `ministry_projects_v2.csv` | 650 | `ministry_projects_v2` |
| `contractor_reports_clean.csv` | 1,163 | `contractor_reports_clean` |
| `finance_disbursements_clean.csv` | 1,648 | `finance_disbursements_clean` |
| `county_reference.csv` | 47 | `county_reference` |

These exist so the [Power BI dashboard](../dashboard/) can be built by
loading local files (Get Data → Text/CSV) — no BigQuery connection or
Google sign-in required. The raw, uncleaned tables and the full cleaning
logic stay in BigQuery / `sql/` for audit; these snapshots are a point-in-
time export, not a live feed.
