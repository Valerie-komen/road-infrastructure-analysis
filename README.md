# Kenya Road Infrastructure — Data Cleaning & Analysis

**Tooling:** Google BigQuery (SQL only) · Dataset: `light-trail-507513-q5.road_infrastructure`

## In short

- **What:** I cleaned and reconciled records from three systems tracking a ministry road-building programme, then analysed progress, spending, and contractor performance.
- **Data:** 665 projects, 1,163 contractor reports, and 1,648 finance disbursements across Kenya's 47 counties.
- **Tools:** SQL in Google BigQuery.
- **Main findings:**
  - A budget parsing error in the existing "clean" table understated the total budget by about KES 112 billion.
  - About 40% of projects (261 out of 650) are behind schedule, and 102 stalled projects hold KES 233.2 billion.
  - 22 projects looked over-disbursed, but this was caused by the same project code being written two different ways, not by overspending.


A ministry road-building program was being tracked across three different systems: **project records, contractor progress reports, and finance disbursements**.
Each system had its own way of recording information, which created inconsistencies in project codes, dates, budgets and other fields.
In this project, I cleaned and reconciled the three datasets before using them for analysis.
The goal was not just to clean the data, but to answer the questions a ministry oversight team would actually care about:
- **Where is the money?**
- **Are projects progressing as planned?**
- **Is spending matching the approved budget?**
- **What issues in the data could affect these conclusions?**

The analysis uncovered several data-quality issues as well as findings around project delays, stalled projects, disbursements, contractor performance and county-level capital commitments.

## What was in the dataset

| Table | Rows | State on arrival |
|---|---|---|
| `ministry_projects_raw` | 665 | Raw, all-STRING |
| `ministry_projects_clean` | 665 | Partially cleaned already (pre-existing) |
| `contractor_reports_raw` | 1,163 | Raw, all-STRING |
| `finance_disbursements_raw` | 1,648 | Raw, all-STRING |
| `county_reference` | 47 | Clean lookup (Kenya's 47 counties) |

## Data Quality Issues I Found and Fixed

While working through the data, I found a few issues that needed to be cleaned up before analysis.

### **1. County names**

There were **158 different spellings** for the 47 counties. Some were just casing differences, some had `"County"` added, and there were also misspellings like `Monbasa` and `Kissumu`.
I standardized them and checked them against the county reference table. **All 47 counties matched correctly.**

### **2. A major budget issue**

This was the biggest finding. Some budgets like `Ksh.4,359,000,000` had been incorrectly read as `0.4359` instead of **4.359 billion**.
This affected **68 out of 695 rows** and understated the total budget by roughly **KES 112 billion**.
I fixed this by removing the `Ksh.` or `KES` prefix first, before cleaning the numbers. This prevented the period in `Ksh.` from being treated as a decimal point.

### **3. Duplicate records**

I found duplicate `project_id` records in both the existing clean table and the raw data. This was also causing some records to be counted more than once when joining tables. I de-duplicated the data before performing the joins.

### **4. Inconsistent project codes**

The same project was sometimes written in different formats, for example:

- `RD-2022-0364`
- `RD20220185`
- `RD - 2023 - 0625`
- `RD-23-0355`
- `0193/2024`

I standardized these into one format: `RD-YYYY-NNNN`.
After cleaning, there were **no unmatched project codes** across the contractor and finance data.

### **5. Different date formats**

The dates came in several formats, including:

- `2024-04-04`
- `07-Dec-2024`
- `29 July 2024`
- `13/06/2022`
- `07/14/2026`

I used a fallback approach to convert them into one consistent date format, while accounting for the Kenyan `DD/MM` convention.

### **6. Currency formatting**

Budgets and disbursements also came in different formats, such as:

- `KES 1,218,000,000`
- `Ksh.1,093,097,585`
- `725000000.00`

I standardized these into numeric values so they could be used reliably for analysis.

## **Some things I didn't "fix"**

Not every unusual value should automatically be changed. For example, completion percentages went as high as **127%**, which is outside the normal 0–100% range.
Instead of deleting the record, I flagged it and capped it at 100% during analysis using `LEAST()`.
There was also a `99` value in the tranche number field whose meaning isn't documented. I left it for clarification rather than guessing.
There were also **22 projects** where disbursement records appeared under two different spellings of the same project code. I was able to reconcile them for analysis, but I didn't combine the amounts because doing so without knowing which spelling is correct would mean making an assumption.

## **Keeping the raw data intact**

Most importantly, I kept the raw data untouched. All cleaning was done in **new tables**, including:

- `ministry_projects_v2`
- `contractor_reports_clean`
- `finance_disbursements_clean`

This means the original data is still available for auditing and comparison. The biggest lesson from this process was that **"clean" data still needs to be questioned**.
I didn't just clean the raw data. I also validated the existing clean tables and found a budget-parsing error that had already made it through the previous cleaning process.

## Key Findings

### **1. 40% of the portfolio is behind schedule**

This was one of the biggest findings. Out of **226 ongoing projects, 197 (87%)** are already past their planned completion date. There are also **72 projects marked "Awarded (Not Started)"**, and **64 (89%)** of these are already past their planned completion date without having started. Together, that means **261 out of 650 projects — about 40% of the entire portfolio — are behind schedule.**

### **2. 102 stalled projects are holding KES 233.2 billion**

There are **102 stalled projects**, which is **15.7% of the entire portfolio**. These projects represent **KES 233.2 billion** in committed budget with no active progress.

| Status | Projects | Budget (bn KES) |
|---|---:|---:|
| Ongoing | 226 | 495.7 |
| Completed | 172 | 403.7 |
| Stalled | 102 | 233.2 |
| Awarded (Not Started) | 72 | 173.1 |
| Under Procurement | 78 | 167.1 |

This stood out because a large amount of committed funding is tied to projects that are currently not progressing.

### **3. National disbursement is 96.1% of the total budget**

The total project budget is **KES 1,472.7 billion**, while total recorded disbursements are **KES 1,415.83 billion**. That gives a national disbursement rate of **96.1%**.
At first glance, this looks close to the total budget. However, the number needs to be interpreted carefully because some projects have a data-quality issue affecting their recorded disbursements.

### **4. 22 projects appear over-disbursed — but the data tells a different story**

There are **22 projects** that appear to have received about **155.6% of their budget** on average. I investigated this further and found that **all 22 projects have disbursement records filed under two different spellings of the same project code**.
For example:

- `RD-2021-0415`
- `RD - 2021 - 0415`

Each spelling has its own tranche entries, which means the same project can appear to have received more money than its allocated budget. The other **628 projects**, where the project code was consistent, averaged **90.3% disbursed**.
This suggests that the apparent over-disbursement is a **data duplication issue rather than evidence of actual overspending**. The 22 project codes should therefore be reconciled against the original finance records before being treated as financial red flags.

### **5. 46 projects are significantly under-disbursed**

There are **46 projects** that have received less than **50% of their allocated budget**.
These projects are worth checking against the stalled-project list to understand whether limited funding could be contributing to delays, or whether the low disbursement is a result of the projects already being stalled.

### **6. Contractor performance varies even at similar contract values**

I also compared contractors with significant project portfolios.

| Contractor | Projects | Value (bn KES) | Stalled | Avg completion % |
|---|---:|---:|---:|---:|
| Cabra International | 38 | 88.3 | 6 | 39.6% |
| China Wu Yi Co Ltd | 33 | 88.2 | 5 | 42.9% |
| Reynolds Construction | 32 | 75.1 | **8** | 51.4% |
| Spencon Services | 28 | 62.7 | 5 | **60.9%** |
| China Overseas Engineering | 24 | 53.2 | 3 | **33.6%** |

Reynolds Construction had the highest number of stalled projects among these contractors, with **8 out of 32 projects** stalled. China Overseas Engineering had an average completion rate of **33.6%**, despite having a similar number of projects to some of the other contractors. Spencon Services had an average completion rate of **60.9%** across its projects.
These differences are useful to investigate further alongside contract terms, project type, location and other factors rather than looking at contractor performance in isolation.

### **7. Bomet has the highest county-level capital commitment**

Bomet had the highest total committed budget at **KES 54.75 billion across 21 projects**. The other counties with high committed budgets were:

- **Siaya:** KES 53.44 billion across 25 projects
- **Nyeri:** KES 46.16 billion across 20 projects
- **Machakos:** KES 45.83 billion across 14 projects
- **Isiolo:** KES 45.63 billion across 20 projects

Machakos stood out because it has a similar level of committed capital but fewer projects. That means its projects have a larger average value, which would be worth exploring further by looking at the mix of projects, such as bridges versus road-length projects.

## **Recommendations**

Based on these findings, I would recommend:

### **1. Reconcile the 22 duplicate-code projects**

The finance team should review the **22 projects with duplicate project-code spellings** against the original source records before national disbursement figures are reported externally.
This could materially change the reported disbursement rate.

### **2. Investigate the 102 stalled projects**

The **102 stalled projects represent KES 233.2 billion** in committed capital. Understanding why these projects stalled should be a priority, especially where large amounts of public funding are tied up.

### **3. Review contractor performance**

Contractors with higher stall counts or lower completion rates should be reviewed against their contract terms, project types and other relevant factors.
The data can help identify where further investigation is needed rather than treating the contractor-level numbers as the explanation on their own.

### **4. Clarify the `tranche_number = 99` value**

The `tranche_number` field normally contains values from **1–4**, but there are records with a value of **99**.
Since its meaning is not documented, I left it unchanged and flagged it for clarification with the finance system owner rather than making an assumption.

### **5. Standardize project codes at data entry**

Project codes should follow **one canonical format** when they are entered into the finance system.
This would help prevent the duplicate-spelling problem from happening again and make it easier to connect project, contractor and finance records reliably.

## **What this analysis showed me**

One of the biggest lessons from this analysis was that the numbers can tell a very different story depending on the quality of the underlying data.
A **96.1% national disbursement rate** looks very different once the duplicate project-code issue is investigated. The same applies to contractor performance, stalled projects and county-level spending.
The analysis wasn't just about calculating percentages. It was about **questioning the numbers, finding what was behind them, and making sure the data actually supported the conclusions.**

### **Tools & Skills**

`SQL` `BigQuery` `Data Cleaning` `Data Quality` `Data Validation` `Data Reconciliation` `Data Analysis` `Data Interpretation`

## Files

- [`sql/01_data_profiling.sql`](sql/01_data_profiling.sql) — diagnostic
  queries used to find every issue listed above
- [`sql/02_cleaning.sql`](sql/02_cleaning.sql) — the cleaning pipeline,
  fully commented with the reasoning behind each transformation
- [`sql/03_analysis_queries.sql`](sql/03_analysis_queries.sql) — the
  business-question queries behind every finding in this report
