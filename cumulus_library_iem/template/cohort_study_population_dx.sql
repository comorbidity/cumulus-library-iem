--  =====================================================================
--  Link Condition to study_population
--  priorities:

--  A. encounter_ref    is NOT null
--  B. recordeddate     is NOT null and encounter_ref IS NULL

-- TIE-BREAK exact-start-date
--  1. encounter starts on the date-mapped day
--  2. narrowest window
--  3. start closest to the date-mapped day
--  4. ordinal
--  5. encounter_ref
-- =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_dx AS
WITH
resource_has_encounter_ref AS (
    SELECT  DISTINCT
            condition_ref
    FROM    core__condition
    WHERE   encounter_ref IS NOT NULL
),

-- Priority A: encounter_ref is NOT null
by_encounter AS (
    SELECT  DISTINCT
            dx.category_code            AS category_code,
            dx.code                     AS code,
            dx.code_display             AS code_display,
            dx.system                   AS system,
            dx.clinicalstatus_code      AS clinicalstatus_code,
            dx.verificationstatus_code  AS verificationstatus_code,
            dx.recordeddate             AS recordeddate,
            dx.onsetdatetime            AS onsetdatetime,
            dx.condition_ref            AS condition_ref,
            dx.encounter_ref            AS dx_condition_encounter_ref,
            sp.encounter_ref            AS link_encounter_ref,
            'encounter_ref'             AS dx_link_method
    FROM    {{ prefix }}__cohort_study_population AS sp
    JOIN    core__condition AS dx
    ON      sp.encounter_ref = dx.encounter_ref
    WHERE   dx.encounter_ref IS NOT NULL
),
-- Priority B: recordeddate is NOT null and encounter_ref IS NULL
date_candidates AS (
    SELECT  DISTINCT
            dx.condition_ref,
            dx.subject_ref,
            DATE(dx.recordeddate) AS recordeddate_day
    FROM    core__condition AS dx
    LEFT JOIN resource_has_encounter_ref AS has_encounter
    ON      dx.condition_ref = has_encounter.condition_ref
    WHERE   dx.encounter_ref    IS      NULL
    AND     dx.recordeddate     IS NOT  NULL
    AND     has_encounter.condition_ref IS NULL
),
date_candidates_ranked AS (
    SELECT  date_candidates.condition_ref,
            sp.encounter_ref AS link_encounter_ref,
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
            link_encounter_ref
    FROM    date_candidates_ranked
    WHERE   dx_link_rank = 1
),
by_recordeddate AS (
    SELECT  DISTINCT
            dx.category_code            AS category_code,
            dx.code                     AS code,
            dx.code_display             AS code_display,
            dx.system                   AS system,
            dx.clinicalstatus_code      AS clinicalstatus_code,
            dx.verificationstatus_code  AS verificationstatus_code,
            dx.recordeddate             AS recordeddate,
            dx.onsetdatetime            AS onsetdatetime,
            dx.condition_ref            AS condition_ref,
            dx.encounter_ref            AS dx_condition_encounter_ref,
            link.link_encounter_ref     AS link_encounter_ref,
            'recordeddate'              AS dx_link_method
    FROM    date_candidates_links AS link
    JOIN    core__condition AS dx
    ON      dx.condition_ref = link.condition_ref
    WHERE   dx.encounter_ref    IS      NULL
      AND   dx.recordeddate     IS NOT  NULL
),
union_link AS (
    SELECT * FROM by_encounter
    UNION ALL
    SELECT * FROM by_recordeddate
)
SELECT  DISTINCT
        union_link.category_code           AS dx_category_code,
        union_link.code                    AS dx_code,
        union_link.code_display            AS dx_display,
        union_link.system                  AS dx_system,
        union_link.clinicalstatus_code     AS dx_clinical_status,
        union_link.verificationstatus_code AS dx_verification_status,
        union_link.recordeddate            AS dx_recorded_date,
        union_link.onsetdatetime           AS dx_onset_date,
        union_link.condition_ref           AS condition_ref,
        union_link.dx_condition_encounter_ref AS dx_condition_encounter_ref,
        union_link.dx_link_method          AS dx_link_method,
        study_population.*
FROM    union_link
JOIN    {{ prefix }}__cohort_study_population AS study_population
ON      study_population.encounter_ref = union_link.link_encounter_ref
;