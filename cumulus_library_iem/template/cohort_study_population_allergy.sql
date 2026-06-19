--  =====================================================================
--  Link AllergyIntolerance to study_population
--  priorities:

--  A. encounter_ref   is NOT null
--  B. recordeddate    is NOT null and encounter_ref IS NULL


-- TIE-BREAK exact-start-date
--  1. encounter starts on the date-mapped day
--  2. narrowest window
--  3. start closest to the date-mapped day
--  4. ordinal
--  5. encounter_ref
-- =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_allergy AS
WITH
resource_has_encounter_ref AS (
    SELECT  DISTINCT
            allergyintolerance_ref
    FROM    core__allergyintolerance
    WHERE   encounter_ref IS NOT NULL
),

-- Priority A: encounter_ref is NOT null
by_encounter AS (
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
            allergy.encounter_ref                   AS allergy_encounter_ref,
            sp.encounter_ref                        AS link_encounter_ref,
            'encounter_ref'                         AS allergy_link_method
    FROM    {{ prefix }}__cohort_study_population   AS sp
    JOIN    core__allergyintolerance                AS allergy
    ON      sp.encounter_ref = allergy.encounter_ref
    WHERE   allergy.encounter_ref IS NOT NULL
),

-- Priority B: recordeddate is NOT null and encounter_ref IS NULL
date_candidates AS (
    SELECT  DISTINCT
            allergy.allergyintolerance_ref      AS allergyintolerance_ref,
            allergy.subject_ref                 as subject_ref,
            DATE(allergy.recordeddate)          AS allergy_day
    FROM    core__allergyintolerance            AS allergy
    LEFT    JOIN resource_has_encounter_ref     AS has_encounter
    ON      allergy.allergyintolerance_ref = has_encounter.allergyintolerance_ref
    WHERE   allergy.encounter_ref   IS      NULL
    AND     allergy.recordeddate    IS NOT  NULL
    AND     has_encounter.allergyintolerance_ref IS NULL
),
date_candidates_ranked AS (
    SELECT  date_candidates.allergyintolerance_ref,
            sp.encounter_ref AS link_encounter_ref,
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
    ON      sp.subject_ref = allergy.subject_ref
    AND     date_candidates.allergy_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day_filled
),
date_candidates_links AS (
    SELECT  allergyintolerance_ref,
            link_encounter_ref
    FROM    date_candidates_ranked
    WHERE   allergy_link_rank = 1
),

by_recordeddate AS (
    SELECT  DISTINCT
            allergy.clinicalstatus_code              AS allergy_clinical_status,
            allergy.verificationstatus_code          AS allergy_verification_status,
            allergy.type                             AS allergy_type,
            allergy.category                         AS allergy_category,
            allergy.criticality                      AS allergy_criticality,
            allergy.code_code                        AS allergy_code,
            allergy.code_system                      AS allergy_system,
            allergy.code_display                     AS allergy_display,
            allergy.recordeddate                     AS allergy_recorded_date,
            DATE(allergy.recordeddate)               AS allergy_link_day,
            allergy.reaction_row                     AS allergy_reaction_row,
            allergy.reaction_substance_code          AS allergy_substance_code,
            allergy.reaction_substance_system        AS allergy_substance_system,
            allergy.reaction_substance_display       AS allergy_substance_display,
            allergy.reaction_manifestation_code      AS allergy_manifestation_code,
            allergy.reaction_manifestation_system    AS allergy_manifestation_system,
            allergy.reaction_manifestation_display   AS allergy_manifestation_display,
            allergy.reaction_severity                AS allergy_severity,
            allergy.allergyintolerance_ref           AS allergyintolerance_ref,
            allergy.encounter_ref                    AS allergy_encounter_ref,
            link.link_encounter_ref                  AS link_encounter_ref,
            'recordeddate'                           AS allergy_link_method
    FROM    date_candidates_links       AS link
    JOIN    core__allergyintolerance    AS allergy
    ON      allergy.allergyintolerance_ref = link.allergyintolerance_ref
    WHERE   allergy.encounter_ref       IS      NULL
    AND     allergy.recordeddate        IS NOT  NULL
),

allergy_links AS (
    SELECT  * FROM    by_encounter
    UNION ALL
    SELECT  * FROM    by_recordeddate
)

SELECT DISTINCT
        allergy_links.allergy_clinical_status       AS allergy_clinical_status,
        allergy_links.allergy_verification_status   AS allergy_verification_status,
        allergy_links.allergy_type                  AS allergy_type,
        allergy_links.allergy_category              AS allergy_category,
        allergy_links.allergy_criticality           AS allergy_criticality,
        allergy_links.allergy_code                  AS allergy_code,
        allergy_links.allergy_system                AS allergy_system,
        allergy_links.allergy_display               AS allergy_display,
        allergy_links.allergy_recorded_date         AS allergy_recorded_date,

        allergy_links.allergy_link_day              AS allergy_link_day,

        allergy_links.allergy_reaction_row          AS allergy_reaction_row,
        allergy_links.allergy_substance_code        AS allergy_substance_code,
        allergy_links.allergy_substance_system      AS allergy_substance_system,
        allergy_links.allergy_substance_display     AS allergy_substance_display,
        allergy_links.allergy_manifestation_code    AS allergy_manifestation_code,
        allergy_links.allergy_manifestation_system  AS allergy_manifestation_system,
        allergy_links.allergy_manifestation_display AS allergy_manifestation_display,
        allergy_links.allergy_severity              AS allergy_severity,

        allergy_links.allergyintolerance_ref        AS allergyintolerance_ref,
        allergy_links.allergy_encounter_ref         AS allergy_encounter_ref,
        allergy_links.allergy_link_method           AS allergy_link_method,
        study_population.*
FROM    allergy_links
JOIN    {{ prefix }}__cohort_study_population AS study_population
ON      study_population.encounter_ref = allergy_links.link_encounter_ref
;