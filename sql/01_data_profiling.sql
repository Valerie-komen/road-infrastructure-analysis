-- =====================================================================
-- Road Infrastructure Analysis — Data Profiling
-- Dataset: light-trail-507513-q5.road_infrastructure
-- Purpose: understand raw table shapes and quantify data-quality issues
--          before writing any cleaning logic.
-- =====================================================================

-- Tables in the dataset and row counts (from `bq show`):
--   contractor_reports_raw      1,163 rows  (all STRING columns)
--   county_reference               47 rows  (county_code, county_name)
--   finance_disbursements_raw   1,648 rows  (all STRING columns)
--   ministry_projects_clean       665 rows  (partially typed — pre-existing)
--   ministry_projects_raw         665 rows  (all STRING columns)

-- 1. Preview raw rows to see actual messy formats
SELECT * FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_raw` LIMIT 10;
SELECT * FROM `light-trail-507513-q5.road_infrastructure.contractor_reports_raw` LIMIT 12;
SELECT * FROM `light-trail-507513-q5.road_infrastructure.finance_disbursements_raw` LIMIT 12;

-- 2. Core data-quality diagnostics (single pass)
WITH d AS (
  SELECT 'dup_project_ids_in_clean' c, CAST(COUNT(*) AS STRING) v
  FROM (SELECT project_id FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_clean`
        GROUP BY project_id HAVING COUNT(*) > 1)
  UNION ALL
  SELECT 'completion_pct_range',
         CONCAT(CAST(MIN(SAFE_CAST(completion_pct AS FLOAT64)) AS STRING), ' to ',
                CAST(MAX(SAFE_CAST(completion_pct AS FLOAT64)) AS STRING))
  FROM `light-trail-507513-q5.road_infrastructure.contractor_reports_raw`
  UNION ALL
  SELECT 'completion_pct_unparseable', CAST(COUNT(*) AS STRING)
  FROM `light-trail-507513-q5.road_infrastructure.contractor_reports_raw`
  WHERE SAFE_CAST(completion_pct AS FLOAT64) IS NULL
  UNION ALL
  SELECT 'distinct_status', STRING_AGG(DISTINCT status, ' | ')
  FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_clean`
  UNION ALL
  SELECT 'distinct_tranche', STRING_AGG(DISTINCT tranche_number, ' | ')
  FROM `light-trail-507513-q5.road_infrastructure.finance_disbursements_raw`
  UNION ALL
  SELECT 'dup_report_ids', CAST(COUNT(*) AS STRING)
  FROM (SELECT report_id FROM `light-trail-507513-q5.road_infrastructure.contractor_reports_raw`
        GROUP BY report_id HAVING COUNT(*) > 1)
  UNION ALL
  SELECT 'dup_disbursement_ids', CAST(COUNT(*) AS STRING)
  FROM (SELECT disbursement_id FROM `light-trail-507513-q5.road_infrastructure.finance_disbursements_raw`
        GROUP BY disbursement_id HAVING COUNT(*) > 1)
  UNION ALL
  SELECT 'distinct_county_count', CAST(COUNT(DISTINCT county) AS STRING)
  FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_raw`
)
SELECT * FROM d;
-- Findings: 15 duplicate project_ids in the "clean" table, completion_pct
-- ranges 0-127 (127 is invalid), 1 unparseable completion_pct, tranche_number
-- includes a "99" sentinel value, 0 duplicate report/disbursement ids,
-- and 158 distinct raw county spellings for Kenya's 47 real counties.

-- 3. County spelling variants (casing, "County" suffix, 2 misspellings:
--    "Monbasa" -> Mombasa, "Kissumu" -> Kisumu)
SELECT county, COUNT(*) n
FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_raw`
GROUP BY county ORDER BY county;

-- 4. Canonical county list (Kenya's 47 counties)
SELECT county_code, county_name
FROM `light-trail-507513-q5.road_infrastructure.county_reference`
ORDER BY county_name;

-- 5. project_code / project_ref format chaos (contractor_reports_raw,
--    finance_disbursements_raw): observed patterns —
--      RD-2022-0364      (canonical: RD-YYYY-NNNN)
--      RD20220185         (digits concatenated, no dashes)
--      RD - 2023 - 0625   (spaces around dashes)
--      RD-23-0355          (2-digit year)
--      0193/2024           (reversed NNNN/YYYY, no "RD" prefix)
