--  =====================================================================
--  Link Condition to study_population
--  priorities:

--  A. encounter_ref maps to a retained study_population encounter
--  B. recordeddate present AND encounter_ref is NULL *or* not retained
--     study_population encounter (date-rescue for orphaned conditions)

-- TIE-BREAK exact-start-date
--  1. encounter starts on the date-mapped day
--  2. narrowest window
--  3. start closest to the date-mapped day
--  4. ordinal
--  5. encounter_ref
-- =====================================================================
CREATE  TABLE   {{ prefix }}__cohort_study_population_dx AS
WITH
-- Priority A: encounter_ref maps to retained study_population encounter
by_encounter AS (
    SELECT  DISTINCT
            dx.category_code            AS dx_category_code,
            dx.code                     AS dx_code,
            dx.code_display             AS dx_display,
            dx.system                   AS dx_system,
            dx.clinicalstatus_code      AS dx_clinical_status,
            dx.verificationstatus_code  AS dx_verification_status,
            dx.recordeddate             AS dx_recorded_date,
            dx.onsetdatetime            AS dx_onset_date,
            dx.condition_ref            AS condition_ref,
            dx.subject_ref              AS subject_ref,
            dx.encounter_ref            AS encounter_ref,
            dx.encounter_ref            AS encounter_ref_link,
            'encounter_ref'             AS encounter_ref_link_col
    FROM    {{ prefix }}__cohort_study_population AS sp
    JOIN    core__condition AS dx
    ON      sp.encounter_ref = dx.encounter_ref
    AND     sp.subject_ref  = dx.subject_ref
    WHERE   dx.encounter_ref IS NOT NULL
),
-- Priority B candidates: recordeddate present AND the condition's encounter_ref is
-- NOT retained study_population encounter. The anti-join against
-- cohort_study_population covers BOTH a true-null encounter_ref (never matches) and
-- an encounter_ref pointing at an encounter dropped by the population filters.
date_candidates AS (
    SELECT  DISTINCT
            dx.condition_ref,
            dx.subject_ref,
            DATE(dx.recordeddate)   AS recordeddate_day
    FROM    core__condition         AS dx
    LEFT JOIN {{ prefix }}__cohort_study_population AS sp
    ON      dx.encounter_ref = sp.encounter_ref
    AND     dx.subject_ref  = sp.subject_ref
    WHERE   dx.recordeddate     IS NOT  NULL
    AND     sp.encounter_ref    IS      NULL
),
date_candidates_ranked AS (
    SELECT  date_candidates.condition_ref,
            sp.encounter_ref AS encounter_ref_link,
            ROW_NUMBER() OVER (
                PARTITION BY date_candidates.condition_ref
                ORDER BY
                    -- Tie-Break #1: encounter starts on the date-mapped day
                    CASE
                        WHEN date_candidates.recordeddate_day = sp.enc_period_start_day
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
                            date_candidates.recordeddate_day
                        )
                    ) ASC,
                    -- Tie-Break #4: encounter ordinal
                    sp.enc_period_ordinal ASC,
                    -- Tie-Break #5: encounter_ref
                    sp.encounter_ref ASC
            ) AS dx_link_rank
    FROM    date_candidates
    JOIN    {{ prefix }}__cohort_study_population AS sp
    ON      sp.subject_ref = date_candidates.subject_ref
    AND     date_candidates.recordeddate_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day_filled
),
date_candidates_links AS (
    SELECT  condition_ref,
            encounter_ref_link
    FROM    date_candidates_ranked
    WHERE   dx_link_rank = 1
),
by_recordeddate AS (
    SELECT  DISTINCT
            dx.category_code            AS dx_category_code,
            dx.code                     AS dx_code,
            dx.code_display             AS dx_display,
            dx.system                   AS dx_system,
            dx.clinicalstatus_code      AS dx_clinical_status,
            dx.verificationstatus_code  AS dx_verification_status,
            dx.recordeddate             AS dx_recorded_date,
            dx.onsetdatetime            AS dx_onset_date,
            dx.condition_ref            AS condition_ref,
            dx.subject_ref              AS subject_ref,
            dx.encounter_ref            AS encounter_ref,
            link.encounter_ref_link     AS encounter_ref_link,
            'recordeddate'              AS encounter_ref_link_col
    FROM    date_candidates_links       AS link
    JOIN    core__condition             AS dx
    ON      dx.condition_ref = link.condition_ref
    WHERE   dx.recordeddate     IS NOT  NULL
),
union_link AS (
    SELECT * FROM by_encounter
    UNION ALL
    SELECT * FROM by_recordeddate
)
SELECT  DISTINCT
        union_link.*
FROM    union_link
;