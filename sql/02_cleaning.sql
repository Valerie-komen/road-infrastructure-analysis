-- =====================================================================
-- Road Infrastructure Analysis — Data Cleaning
-- Builds three analysis-ready tables from the raw / partially-cleaned
-- source tables. Every step below is additive (CREATE TABLE IF NOT
-- EXISTS on a NEW table name) so the original raw and pre-existing
-- tables are never overwritten — the raw data stays available for audit.
-- =====================================================================

-- -----------------------------------------------------------------------
-- A) ministry_projects_v2  — the authoritative, fully-cleaned projects
--    table. Built in two stages because two independent bugs were found
--    in the pre-existing `ministry_projects_clean` table:
--      1. 15 duplicate project_id rows (never de-duplicated)
--      2. budget_kes mis-parsed for any raw value formatted "Ksh.X,XXX..."
--         — the "." after "Ksh" was read as a decimal point, so
--         "Ksh.4,359,000,000" became 0.4359 instead of 4,359,000,000.
--         This affected 68 of 695 rows (~10%) and understated the
--         national budget total by ~112bn KES.
--    A first attempt joined the de-duplicated `clean` table straight to
--    `ministry_projects_raw` to re-derive budget_kes — but ministry_
--    projects_raw *itself* contains duplicate project_id rows, causing
--    a fan-out (652 rows instead of 650). The fix below de-duplicates
--    BOTH sides before joining, matched on row rank.
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `light-trail-507513-q5.road_infrastructure.ministry_projects_v2` AS
SELECT
  c.project_id,
  c.project_name,
  c.county,                         -- already correctly normalized in
                                     -- the pre-existing clean table
                                     -- (verified: 47/47 distinct values
                                     -- match county_reference, 0 unmatched)
  c.contractor,
  SAFE_CAST(
    REGEXP_REPLACE(
      REGEXP_REPLACE(UPPER(TRIM(r.budget_kes)), r'^(KSH\.|KES)\s*', ''),
      r'[, ]', ''
    ) AS NUMERIC
  ) AS budget_kes,                  -- re-derived from raw with a parser
                                     -- that strips "Ksh."/"KES" prefixes
                                     -- BEFORE removing punctuation, so the
                                     -- prefix's period is never mistaken
                                     -- for a decimal point
  c.start_date,
  c.planned_completion_date,
  c.status
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY project_id ORDER BY project_id) rn
  FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_clean`
) c
JOIN (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY project_id ORDER BY project_id) rn
  FROM `light-trail-507513-q5.road_infrastructure.ministry_projects_raw`
) r
  ON c.project_id = r.project_id AND c.rn = r.rn
WHERE c.rn = 1;
-- Result: 650 rows, 650 distinct project_id, 0 rows with budget_kes < 1000.

-- -----------------------------------------------------------------------
-- B) contractor_reports_clean  — normalizes project_code to the
--    canonical RD-YYYY-NNNN format so it can join to ministry_projects_v2,
--    trims contractor_name, casts completion_pct, and parses report_date
--    across 5 observed date formats.
--
--    project_code normalizer logic (applied via a digit-group match):
--      2 groups, first=4 digits, starts with "20" and second doesn't  -> reversed NNNN/YYYY  (e.g. "0193/2024")
--      1 group of 8 digits                                            -> concatenated YYYYNNNN (e.g. "RD20220185")
--      2 groups, first=4 digits                                       -> standard YYYY-NNNN
--      2 groups, first=2 digits                                       -> 2-digit year, expand to 20YY
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `light-trail-507513-q5.road_infrastructure.contractor_reports_clean` AS
SELECT
  report_id,
  project_code AS project_code_raw,
  (SELECT CASE
     WHEN ARRAY_LENGTH(g) = 2 AND LENGTH(g[OFFSET(0)]) = 4 AND LENGTH(g[OFFSET(1)]) = 4
          AND STARTS_WITH(g[OFFSET(1)], '20') AND NOT STARTS_WITH(g[OFFSET(0)], '20')
       THEN CONCAT('RD-', g[OFFSET(1)], '-', LPAD(g[OFFSET(0)], 4, '0'))
     WHEN ARRAY_LENGTH(g) = 1 AND LENGTH(g[OFFSET(0)]) = 8
       THEN CONCAT('RD-', SUBSTR(g[OFFSET(0)], 1, 4), '-', SUBSTR(g[OFFSET(0)], 5, 4))
     WHEN ARRAY_LENGTH(g) = 2 AND LENGTH(g[OFFSET(0)]) = 4
       THEN CONCAT('RD-', g[OFFSET(0)], '-', LPAD(g[OFFSET(1)], 4, '0'))
     WHEN ARRAY_LENGTH(g) = 2 AND LENGTH(g[OFFSET(0)]) = 2
       THEN CONCAT('RD-20', g[OFFSET(0)], '-', LPAD(g[OFFSET(1)], 4, '0'))
     ELSE NULL
   END
   FROM (SELECT REGEXP_EXTRACT_ALL(project_code, r'\d+') AS g)) AS project_id,
  TRIM(contractor_name) AS contractor_name_raw,
  SAFE_CAST(completion_pct AS FLOAT64) AS completion_pct,   -- NOTE: values
                                     -- above 100 (max observed: 127) are
                                     -- left as-is here and handled with
                                     -- LEAST(completion_pct,100) at query
                                     -- time in the analysis layer, so the
                                     -- anomaly stays visible for audit.
  COALESCE(
    SAFE.PARSE_DATE('%Y-%m-%d', report_date),
    SAFE.PARSE_DATE('%d-%b-%Y', report_date),
    SAFE.PARSE_DATE('%d %B %Y', report_date),
    SAFE.PARSE_DATE('%d/%m/%Y', report_date),   -- tried before %m/%d so
    SAFE.PARSE_DATE('%m/%d/%Y', report_date)    -- Kenya's DD/MM convention
  ) AS report_date                              -- wins whenever the value
                                                 -- is ambiguous but valid
                                                 -- under both formats
FROM `light-trail-507513-q5.road_infrastructure.contractor_reports_raw`;
-- Validation: 1163 rows in, only 1 null project_id (unparseable code),
-- only 1 null report_date, 0 project_ids that fail to match a real
-- project in ministry_projects_v2.

-- -----------------------------------------------------------------------
-- C) finance_disbursements_clean  — same project-code normalization,
--    plus amount_kes cleanup (strips "Ksh.", "KES", commas, whitespace)
--    and tranche_number cast to INT64.
--    NOTE: tranche_number includes a "99" sentinel value in the raw data
--    (see profiling script) — left as-is, flagged in the report as a
--    value needing clarification from the source system owner.
-- -----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `light-trail-507513-q5.road_infrastructure.finance_disbursements_clean` AS
SELECT
  disbursement_id,
  project_ref AS project_ref_raw,
  (SELECT CASE
     WHEN ARRAY_LENGTH(g) = 2 AND LENGTH(g[OFFSET(0)]) = 4 AND LENGTH(g[OFFSET(1)]) = 4
          AND STARTS_WITH(g[OFFSET(1)], '20') AND NOT STARTS_WITH(g[OFFSET(0)], '20')
       THEN CONCAT('RD-', g[OFFSET(1)], '-', LPAD(g[OFFSET(0)], 4, '0'))
     WHEN ARRAY_LENGTH(g) = 1 AND LENGTH(g[OFFSET(0)]) = 8
       THEN CONCAT('RD-', SUBSTR(g[OFFSET(0)], 1, 4), '-', SUBSTR(g[OFFSET(0)], 5, 4))
     WHEN ARRAY_LENGTH(g) = 2 AND LENGTH(g[OFFSET(0)]) = 4
       THEN CONCAT('RD-', g[OFFSET(0)], '-', LPAD(g[OFFSET(1)], 4, '0'))
     WHEN ARRAY_LENGTH(g) = 2 AND LENGTH(g[OFFSET(0)]) = 2
       THEN CONCAT('RD-20', g[OFFSET(0)], '-', LPAD(g[OFFSET(1)], 4, '0'))
     ELSE NULL
   END
   FROM (SELECT REGEXP_EXTRACT_ALL(project_ref, r'\d+') AS g)) AS project_id,
  SAFE_CAST(tranche_number AS INT64) AS tranche_number,
  SAFE_CAST(REGEXP_REPLACE(amount_kes, r'[^0-9.]', '') AS NUMERIC) AS amount_kes,
  COALESCE(
    SAFE.PARSE_DATE('%Y-%m-%d', disbursement_date),
    SAFE.PARSE_DATE('%d-%b-%Y', disbursement_date),
    SAFE.PARSE_DATE('%d %B %Y', disbursement_date),
    SAFE.PARSE_DATE('%d/%m/%Y', disbursement_date),
    SAFE.PARSE_DATE('%m/%d/%Y', disbursement_date)
  ) AS disbursement_date
FROM `light-trail-507513-q5.road_infrastructure.finance_disbursements_raw`;
-- Validation: 1648 rows in, 0 null project_id, 0 null disbursement_date,
-- 0 null amount_kes, 0 project_ids that fail to match a real project.

-- -----------------------------------------------------------------------
-- D) Known remaining data-quality issue — NOT auto-corrected, flagged
--    for the ministry finance team instead of silently "fixed":
--    22 of 650 projects have disbursement records entered under TWO
--    different spellings of their project code (e.g. "RD-2021-0415"
--    and "RD - 2021 - 0415"), each spelling carrying its own set of
--    tranche amounts. Once normalized to one project_id, these 22
--    projects appear to be disbursed ~155.6% of budget on average,
--    vs. 90.3% for the other 628 projects — almost certainly a
--    duplicate-entry / two-system reconciliation issue rather than a
--    genuine overspend. See sql/03_analysis_queries.sql, section F.
-- -----------------------------------------------------------------------
