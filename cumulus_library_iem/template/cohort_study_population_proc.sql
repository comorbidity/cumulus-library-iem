--  =====================================================================
--  Link Procedure to study_population
--
--  PRIORITIES
--    A. encounter_ref   is NOT null
--    B. performeddatetime / performedperiod_start is NOT null  AND  encounter_ref IS NULL
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
CREATE TABLE {{ prefix }}__cohort_study_population_proc AS
WITH
resource_has_encounter_ref AS (
    SELECT  DISTINCT
            procedure_ref
    FROM    core__procedure
    WHERE   encounter_ref IS NOT NULL
),

-- Priority A: native encounter_ref.
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
                                    AS proc_link_day,
            proc.procedure_ref      AS procedure_ref,
            proc.encounter_ref      AS proc_encounter_ref,
            sp.encounter_ref        AS link_encounter_ref,
            'encounter_ref'         AS proc_link_method
    FROM    {{ prefix }}__cohort_study_population AS sp
    JOIN    core__procedure         AS proc
    ON      sp.encounter_ref = proc.encounter_ref
    WHERE   proc.encounter_ref      IS NOT NULL
),

-- Priority B candidates: date present, no encounter_ref, never natively linked.
date_candidates AS (
    SELECT  DISTINCT
            proc.procedure_ref,
            proc.subject_ref,
            COALESCE(DATE(proc.performeddatetime), DATE(proc.performedperiod_start)) AS candidate_day
    FROM    core__procedure AS proc
    LEFT JOIN resource_has_encounter_ref AS has_encounter
    ON      proc.procedure_ref = has_encounter.procedure_ref
    WHERE   proc.encounter_ref IS NULL
    AND     COALESCE(DATE(proc.performeddatetime), DATE(proc.performedperiod_start)) IS NOT NULL
    AND     has_encounter.procedure_ref IS NULL
),
date_candidates_ranked AS (
    SELECT  date_candidates.procedure_ref,
            sp.encounter_ref AS link_encounter_ref,
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
            link_encounter_ref
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
            COALESCE(DATE(proc.performeddatetime), DATE(proc.performedperiod_start)) AS proc_link_day,
            proc.procedure_ref      AS procedure_ref,
            proc.encounter_ref      AS proc_encounter_ref,
            link.link_encounter_ref AS link_encounter_ref,
            'performed_date'        AS proc_link_method
    FROM    date_candidates_links   AS link
    JOIN    core__procedure         AS proc
    ON      proc.procedure_ref = link.procedure_ref
    WHERE   proc.encounter_ref      IS NULL
    AND     COALESCE(DATE(proc.performeddatetime), DATE(proc.performedperiod_start)) IS NOT NULL
),
union_all AS (
    SELECT * FROM by_encounter
    UNION ALL
    SELECT * FROM by_date
)
SELECT  DISTINCT
        union_all.proc_category_code    AS proc_category_code,
        union_all.proc_category_display AS proc_category_display,
        union_all.proc_category_system  AS proc_category_system,
        union_all.proc_status           AS proc_status,
        union_all.proc_code             AS proc_code,
        union_all.proc_display          AS proc_display,
        union_all.proc_system           AS proc_system,
        union_all.proc_link_day         AS proc_link_day,
        union_all.procedure_ref         AS procedure_ref,
        union_all.proc_encounter_ref    AS proc_encounter_ref,
        union_all.proc_link_method      AS proc_link_method,
        study_population.*
FROM    union_all
JOIN    {{ prefix }}__cohort_study_population AS study_population
ON      study_population.encounter_ref = union_all.link_encounter_ref
;