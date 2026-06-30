--  =====================================================================
--  Link AllergyIntolerance to study_population
--  priorities:

--  A. encounter_ref maps to a retained study_population encounter
--  B. recordeddate present AND encounter_ref is NULL *or* not retained
--     study_population encounter (date-rescue for orphaned allergies)

-- TIE-BREAK exact-start-date
--  1. encounter starts on the date-mapped day
--  2. narrowest window
--  3. start closest to the date-mapped day
--  4. ordinal
--  5. encounter_ref
-- =====================================================================
CREATE  TABLE   {{ prefix }}__cohort_study_population_allergy AS
WITH
-- Priority A: encounter_ref maps to retained study_population encounter
by_encounter AS (
    SELECT
            allergy.clinicalstatus_code             AS allergy_clinical_status,
            allergy.verificationstatus_code         AS allergy_verification_status,
            allergy."type"                          AS allergy_type,
            allergy.category                        AS allergy_category,
            allergy.criticality                     AS allergy_criticality,
            allergy.code_code                       AS allergy_code,
            allergy.code_system                     AS allergy_system,
            allergy.code_display                    AS allergy_display,
            allergy.recordeddate                    AS allergy_recorded_date,
            DATE(allergy.recordeddate)              AS allergy_link_day,
            allergy.reaction_row                    AS allergy_reaction_row,
            allergy.reaction_substance_code         AS allergy_substance_code,
            allergy.reaction_substance_system       AS allergy_substance_system,
            allergy.reaction_substance_display      AS allergy_substance_display,
            allergy.reaction_manifestation_code     AS allergy_manifestation_code,
            allergy.reaction_manifestation_system   AS allergy_manifestation_system,
            allergy.reaction_manifestation_display  AS allergy_manifestation_display,
            allergy.reaction_severity               AS allergy_severity,
            allergy.allergyintolerance_ref          AS allergyintolerance_ref,
            sp.subject_ref                          AS subject_ref,
            sp.encounter_ref                        AS encounter_ref,
            sp.encounter_ref                        AS encounter_ref_link,
            'encounter_ref'                         AS encounter_ref_link_col
    FROM    {{ prefix }}__cohort_study_population   AS sp
    JOIN    core__allergyintolerance                AS allergy
    ON      sp.encounter_ref = allergy.encounter_ref
    AND     sp.subject_ref   = allergy.patient_ref
    WHERE   allergy.encounter_ref IS NOT NULL
),

-- Priority B candidates: recordeddate present AND the allergy's encounter_ref is
-- NOT retained study_population encounter. The anti-join against
-- cohort_study_population covers BOTH a true-null encounter_ref (never matches) and
-- an encounter_ref pointing at an encounter dropped by the population filters.
-- NOTE: this anti-join depends on subject_ref being formatted consistently between
-- core__allergyintolerance.patient_ref and cohort_study_population.subject_ref.
date_candidates AS (
    SELECT  DISTINCT
            allergy.allergyintolerance_ref  AS allergyintolerance_ref,
            allergy.patient_ref             AS subject_ref,
            DATE(allergy.recordeddate)      AS allergy_day
    FROM    core__allergyintolerance        AS allergy
    LEFT JOIN {{ prefix }}__cohort_study_population AS sp
    ON      allergy.encounter_ref = sp.encounter_ref
    AND     allergy.patient_ref   = sp.subject_ref
    WHERE   allergy.recordeddate  IS NOT  NULL
    AND     sp.encounter_ref      IS      NULL
),
date_candidates_ranked AS (
    SELECT  date_candidates.allergyintolerance_ref,
            sp.encounter_ref AS encounter_ref_link,
            ROW_NUMBER() OVER (
                PARTITION BY date_candidates.allergyintolerance_ref
                ORDER BY
                    -- Tie-Break #1: encounter starts on the date-mapped day
                    CASE
                        WHEN date_candidates.allergy_day = sp.enc_period_start_day
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
                            date_candidates.allergy_day
                        )
                    ) ASC,
                    -- Tie-Break #4: encounter ordinal
                    sp.enc_period_ordinal ASC,
                    -- Tie-Break #5: encounter_ref
                    sp.encounter_ref ASC
            ) AS allergy_link_rank
    FROM    date_candidates
    JOIN    {{ prefix }}__cohort_study_population AS sp
    ON      sp.subject_ref = date_candidates.subject_ref
    AND     date_candidates.allergy_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day_filled
),
date_candidates_links AS (
    SELECT  allergyintolerance_ref,
            encounter_ref_link
    FROM    date_candidates_ranked
    WHERE   allergy_link_rank = 1
),

by_recordeddate AS (
    SELECT  DISTINCT
            allergy.clinicalstatus_code             AS allergy_clinical_status,
            allergy.verificationstatus_code         AS allergy_verification_status,
            allergy."type"                          AS allergy_type,
            allergy.category                        AS allergy_category,
            allergy.criticality                     AS allergy_criticality,
            allergy.code_code                       AS allergy_code,
            allergy.code_system                     AS allergy_system,
            allergy.code_display                    AS allergy_display,
            allergy.recordeddate                    AS allergy_recorded_date,
            DATE(allergy.recordeddate)              AS allergy_link_day,
            allergy.reaction_row                    AS allergy_reaction_row,
            allergy.reaction_substance_code         AS allergy_substance_code,
            allergy.reaction_substance_system       AS allergy_substance_system,
            allergy.reaction_substance_display      AS allergy_substance_display,
            allergy.reaction_manifestation_code     AS allergy_manifestation_code,
            allergy.reaction_manifestation_system   AS allergy_manifestation_system,
            allergy.reaction_manifestation_display  AS allergy_manifestation_display,
            allergy.reaction_severity               AS allergy_severity,
            allergy.allergyintolerance_ref          AS allergyintolerance_ref,
            allergy.patient_ref                     AS subject_ref,
            allergy.encounter_ref                   AS encounter_ref,
            link.encounter_ref_link                 AS encounter_ref_link,
            'recordeddate'                          AS encounter_ref_link_col
    FROM    date_candidates_links       AS link
    JOIN    core__allergyintolerance    AS allergy
    ON      allergy.allergyintolerance_ref = link.allergyintolerance_ref
    WHERE   allergy.recordeddate        IS NOT  NULL
),
union_link AS (
    SELECT  * FROM    by_encounter
    UNION ALL
    SELECT  * FROM    by_recordeddate
)
SELECT  DISTINCT
        union_link.*
FROM    union_link
;
