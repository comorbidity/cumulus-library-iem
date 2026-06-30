--  =====================================================================
--  Link Procedure to study_population
--
--  PRIORITIES
--    A. encounter_ref maps to a retained study_population encounter
--    B. performeddatetime / performedperiod_start present AND encounter_ref is NULL
--       *or* not retained study_population encounter (date-rescue for orphans)
--
--  TIE-BREAK (exact-start-date)
--    1. encounter starts on the date-mapped day
--    2. narrowest window
--    3. start closest to the date-mapped day
--    4. ordinal
--    5. encounter_ref
--
--  Shared skeleton across rx / dx / proc / doc / diag / allergy. Only the
--  resource table, ref, date expression, and columns differ.
--  =====================================================================
CREATE  TABLE   {{ prefix }}__cohort_study_population_proc AS
WITH
-- Priority A: encounter_ref maps to retained study_population encounter.
by_encounter AS (
    SELECT  DISTINCT
            proc.category_code      AS proc_category_code,
            proc.category_display   AS proc_category_display,
            proc.category_system    AS proc_category_system,
            proc.status             AS proc_status,
            proc.code_code          AS proc_code,
            proc.code_display       AS proc_display,
            proc.code_system        AS proc_system,
            COALESCE(DATE(proc.performeddatetime), DATE(proc.performedperiod_start))
                                    AS proc_performed_day,
            proc.procedure_ref      AS procedure_ref,

            proc.subject_ref        AS subject_ref,
            proc.encounter_ref      AS encounter_ref,
            proc.encounter_ref      AS encounter_ref_link,
            'encounter_ref'         AS encounter_ref_link_col
    FROM    {{ prefix }}__cohort_study_population AS sp
    JOIN    core__procedure         AS proc
    ON      sp.encounter_ref = proc.encounter_ref
    AND     sp.subject_ref   = proc.subject_ref
    WHERE   proc.encounter_ref      IS NOT NULL
),

-- Priority B candidates: date present AND the procedure's encounter_ref is NOT a
-- retained study_population encounter. The anti-join against
-- cohort_study_population covers BOTH a true-null encounter_ref (never matches) and
-- an encounter_ref pointing at an encounter dropped by the population filters.
-- NOTE: anti-join depends on consistent subject_ref formatting across the two tables.
date_candidates AS (
    SELECT  DISTINCT
            proc.procedure_ref,
            proc.subject_ref,
            COALESCE(DATE(proc.performeddatetime), DATE(proc.performedperiod_start))
                            AS candidate_day
    FROM    core__procedure AS proc
    LEFT JOIN {{ prefix }}__cohort_study_population AS sp
    ON      proc.encounter_ref = sp.encounter_ref
    AND     proc.subject_ref   = sp.subject_ref
    WHERE   COALESCE(DATE(proc.performeddatetime), DATE(proc.performedperiod_start)) IS NOT NULL
    AND     sp.encounter_ref   IS NULL
),
date_candidates_ranked AS (
    SELECT  date_candidates.procedure_ref,
            sp.encounter_ref AS encounter_ref_link,
            ROW_NUMBER() OVER (
                PARTITION BY date_candidates.procedure_ref
                ORDER BY
                    -- Tie-Break #1: encounter starts on the date-mapped day
                    CASE
                        WHEN date_candidates.candidate_day = sp.enc_period_start_day
                        THEN 0 ELSE 1
                    END,
                    -- Tie-Break #2: narrowest window
                    DATE_DIFF(
                        'day',
                        sp.enc_period_start_day,
                        sp.enc_period_end_day_filled
                    ) ASC,
                    -- Tie-Break #3: start closest to the date-mapped day
                    ABS(
                        DATE_DIFF(
                            'day',
                            sp.enc_period_start_day,
                            date_candidates.candidate_day
                        )
                    ) ASC,
                    -- Tie-Break #4: encounter ordinal
                    sp.enc_period_ordinal ASC,
                    -- Tie-Break #5: encounter_ref
                    sp.encounter_ref ASC
            ) AS link_rank
    FROM    date_candidates
    JOIN    {{ prefix }}__cohort_study_population AS sp
    ON      sp.subject_ref = date_candidates.subject_ref
    AND     date_candidates.candidate_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day_filled
),
date_candidates_links AS (
    SELECT  procedure_ref,
            encounter_ref_link
    FROM    date_candidates_ranked
    WHERE   link_rank = 1
),
by_date AS (
    SELECT  DISTINCT
            proc.category_code      AS proc_category_code,
            proc.category_display   AS proc_category_display,
            proc.category_system    AS proc_category_system,
            proc.status             AS proc_status,
            proc.code_code          AS proc_code,
            proc.code_display       AS proc_display,
            proc.code_system        AS proc_system,
            COALESCE(DATE(proc.performeddatetime), DATE(proc.performedperiod_start)) AS proc_performed_day,
            proc.procedure_ref      AS procedure_ref,

            proc.subject_ref        AS subject_ref,
            proc.encounter_ref      AS encounter_ref,
            link.encounter_ref_link AS encounter_ref_link,
            'performed_date'        AS encounter_ref_link_col
    FROM    date_candidates_links   AS link
    JOIN    core__procedure         AS proc
    ON      proc.procedure_ref = link.procedure_ref
    WHERE   COALESCE(DATE(proc.performeddatetime), DATE(proc.performedperiod_start)) IS NOT NULL
),
union_all AS (
    SELECT * FROM by_encounter
    UNION ALL
    SELECT * FROM by_date
)
SELECT  DISTINCT
        union_all.*
FROM    union_all
;
