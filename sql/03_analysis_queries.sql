-- =====================================================================
-- Road Infrastructure Analysis — Business Questions
-- All queries run against the cleaned tables built in 02_cleaning.sql:
--   ministry_projects_v2, contractor_reports_clean,
--   finance_disbursements_clean, county_reference
-- =====================================================================

-- A) Portfolio status overview — where is the money, and what state is it in?
SELECT
  status,
  COUNT(*) n,
  ROUND(SUM(budget_kes)/1e9, 1) budget_bn,
  COUNTIF(status IN ('Ongoing','Awarded (Not Started)')
          AND planned_completion_date < CURRENT_DATE()) n_overdue
FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_v2`
GROUP BY status
ORDER BY budget_bn DESC;

-- B) National budget vs. disbursement reconciliation
SELECT
  COUNT(*) n_projects,
  ROUND(SUM(budget_kes)/1e9, 2) total_budget_bn,
  ROUND(SUM(disbursed)/1e9, 2) total_disbursed_bn,
  ROUND(SUM(disbursed)/SUM(budget_kes)*100, 1) pct_disbursed,
  COUNTIF(disbursed > budget_kes*1.05) n_over_5pct,
  COUNTIF(disbursed < budget_kes*0.5) n_under_50pct
FROM (
  SELECT p.project_id, p.budget_kes, SUM(f.amount_kes) disbursed
  FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_v2` p
  LEFT JOIN `light-trail-507513-q5.road_infrastructure.finance_disbursements_clean` f
    ON p.project_id = f.project_id
  GROUP BY p.project_id, p.budget_kes
);

-- C) Top 10 counties by capital committed, with stalled/overdue counts
SELECT
  county,
  COUNT(*) n_projects,
  ROUND(SUM(budget_kes)/1e9, 2) budget_bn,
  COUNTIF(status = 'Stalled') n_stalled,
  COUNTIF(status IN ('Ongoing','Awarded (Not Started)')
          AND planned_completion_date < CURRENT_DATE()) n_overdue
FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_v2`
GROUP BY county
ORDER BY budget_bn DESC
LIMIT 10;

-- D) Contractor performance — value delivered vs. completion rate vs. stalls
SELECT
  p.contractor,
  COUNT(*) n_projects,
  ROUND(SUM(p.budget_kes)/1e9, 2) budget_bn,
  COUNTIF(p.status = 'Stalled') n_stalled,
  ROUND(AVG(r.avg_completion), 1) avg_completion_pct
FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_v2` p
LEFT JOIN (
  SELECT project_id, AVG(LEAST(completion_pct, 100)) avg_completion
  FROM `light-trail-507513-q5.road_infrastructure.contractor_reports_clean`
  WHERE completion_pct IS NOT NULL AND completion_pct >= 0
  GROUP BY project_id
) r ON p.project_id = r.project_id
GROUP BY p.contractor
ORDER BY budget_bn DESC
LIMIT 12;

-- E) Specific over-disbursed projects (>5% above budget) — audit list
SELECT
  project_id, project_name, county, contractor, status,
  ROUND(budget_kes/1e6, 1) budget_m,
  ROUND(disbursed/1e6, 1) disbursed_m,
  ROUND((disbursed/budget_kes - 1)*100, 0) pct_over
FROM (
  SELECT p.project_id, p.project_name, p.county, p.contractor, p.status,
         p.budget_kes, SUM(f.amount_kes) disbursed
  FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_v2` p
  JOIN `light-trail-507513-q5.road_infrastructure.finance_disbursements_clean` f
    ON p.project_id = f.project_id
  GROUP BY 1,2,3,4,5,6
)
WHERE disbursed > budget_kes * 1.05
ORDER BY pct_over DESC
LIMIT 10;

-- F) Root-cause check for (E): does over-disbursement correlate with a
--    project code being entered under 2 different spellings?
SELECT
  n_raw_refs,
  COUNT(*) n_projects,
  ROUND(AVG(pct_disbursed), 1) avg_pct_disbursed
FROM (
  SELECT p.project_id,
         COUNT(DISTINCT f.project_ref_raw) n_raw_refs,
         SUM(f.amount_kes) / p.budget_kes * 100 pct_disbursed
  FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_v2` p
  JOIN `light-trail-507513-q5.road_infrastructure.finance_disbursements_clean` f
    ON p.project_id = f.project_id
  GROUP BY p.project_id, p.budget_kes
)
GROUP BY n_raw_refs
ORDER BY n_raw_refs;
-- Result: every one of the 22 over-disbursed projects has disbursement
-- rows under exactly 2 distinct raw project-code spellings (628 projects
-- with 1 spelling average 90.3% disbursed; 22 projects with 2 spellings
-- average 155.6%). This is a source-system duplicate-entry pattern, not
-- evidence of real overspending — recommend the ministry finance team
-- reconcile these 22 project codes against their disbursement ledger.
