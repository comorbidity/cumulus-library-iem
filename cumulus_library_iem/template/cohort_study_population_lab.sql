-- Dependency tree:
--  cohort_study_period
--  cohort_study_population
--  cohort_study_population_obs_base
--  cohort_study_population_lab_base
--  cohort_study_population_lab (this table)
--  =====================================================================
--  Link Observation laboratory to study_population
--  priorities:

--  A. encounter_ref   is NOT null
--  B. effectivedatetime is NOT null and encounter_ref IS NULL

-- TIE-BREAK exact-start-date
--  1. encounter starts on the date-mapped day
--  2. narrowest window
--  3. start closest to the date-mapped day
--  4. ordinal
--  5. encounter_ref
-- =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_lab AS
WITH
resource_has_encounter AS (
    SELECT  DISTINCT
            subject_ref,
            encounter_ref,
            enc_period_ordinal,
            enc_period_start_day,
            enc_period_end_day_filled AS enc_period_end_day
    FROM    {{ prefix }}__cohort_study_population
    WHERE   encounter_ref IS NOT NULL
),
-- Priority A: encounter_ref is NOT null
by_encounter AS (
    SELECT  DISTINCT
            lab.observation_code                  AS observation_code,
            lab.observation_system                AS observation_system,

            lab.valuecodeableconcept_code         AS valuecodeableconcept_code,
            lab.valuecodeableconcept_display      AS valuecodeableconcept_display,
            lab.valuecodeableconcept_system       AS valuecodeableconcept_system,

            lab.effectivedatetime                 AS effectivedatetime,
            lab.effectivedatetime_day             AS effectivedatetime_day,

            lab.interpretation_code               AS interpretation_code,
            lab.interpretation_system             AS interpretation_system,
            lab.interpretation_display            AS interpretation_display,

            lab.valuequantity_value               AS valuequantity_value,
            lab.valuequantity_comparator          AS valuequantity_comparator,
            lab.valuequantity_unit                AS valuequantity_unit,
            lab.valuequantity_system              AS valuequantity_system,
            lab.valuequantity_code                AS valuequantity_code,

            lab.valuestring                       AS valuestring,

            lab.dataabsentreason_code             AS dataabsentreason_code,
            lab.dataabsentreason_system           AS dataabsentreason_system,
            lab.dataabsentreason_display          AS dataabsentreason_display,

            lab.status                            AS status,
            lab.specimen_ref                      AS specimen_ref,
            lab.observation_ref                   AS observation_ref,

            lab.observation_encounter_ref         AS lab_observation_encounter_ref,
            sp.encounter_ref                      AS link_encounter_ref,
            'encounter_ref'                       AS lab_link_method

    FROM    {{ prefix }}__cohort_study_population_lab_base AS lab
    JOIN    resource_has_encounter AS sp
    ON      sp.encounter_ref = lab.observation_encounter_ref
    WHERE   lab.observation_encounter_ref IS NOT NULL
),

date_candidates AS (
    SELECT  DISTINCT
            observation_ref,
            subject_ref,
            effectivedatetime_day AS effectivedate_day
    FROM    {{ prefix }}__cohort_study_population_lab_base
    WHERE   obs_has_encounter = 0
    AND     observation_encounter_ref   IS      NULL
    AND     effectivedatetime_day       IS NOT  NULL
),

--
-- Priority B: effectivedatetime is NOT null and encounter_ref IS NULL
date_candidates_ranked AS (
    SELECT  lab.observation_ref,
            sp.encounter_ref AS link_encounter_ref,

            ROW_NUMBER() OVER (
                PARTITION BY lab.observation_ref
                ORDER BY
                    -- Tie-Break #1: encounter starts on the date-mapped day
                    CASE
                        WHEN lab.effectivedate_day = sp.enc_period_start_day
                        THEN 0 ELSE 1
                    END,
                    -- Tie-Break #2: narrowest window
                    DATE_DIFF(
                        'day',
                        sp.enc_period_start_day,
                        sp.enc_period_end_day
                    ) ASC,
                    -- Tie-Break #3: start closest to the date-mapped day
                    ABS(
                        DATE_DIFF(
                            'day',
                            sp.enc_period_start_day,
                            lab.effectivedate_day
                        )
                    ) ASC,
                    -- Tie-Break #4: encounter ordinal
                    sp.enc_period_ordinal ASC,
                    -- Tie-Break #5: encounter_ref
                    sp.encounter_ref ASC
            ) AS lab_link_rank
    FROM    date_candidates AS lab
    JOIN    resource_has_encounter AS sp
    ON      sp.subject_ref = lab.subject_ref
    AND     lab.effectivedate_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day
),

date_candidates_links AS (
    SELECT
        observation_ref,
        link_encounter_ref
    FROM date_candidates_ranked
    WHERE lab_link_rank = 1
),
by_effectivedate AS (
    SELECT DISTINCT
        lab.observation_code                  AS observation_code,
        lab.observation_system                AS observation_system,

        lab.valuecodeableconcept_code         AS valuecodeableconcept_code,
        lab.valuecodeableconcept_display      AS valuecodeableconcept_display,
        lab.valuecodeableconcept_system       AS valuecodeableconcept_system,

        lab.effectivedatetime                 AS effectivedatetime,
        lab.effectivedatetime_day             AS effectivedatetime_day,

        lab.interpretation_code               AS interpretation_code,
        lab.interpretation_system             AS interpretation_system,
        lab.interpretation_display            AS interpretation_display,

        lab.valuequantity_value               AS valuequantity_value,
        lab.valuequantity_comparator          AS valuequantity_comparator,
        lab.valuequantity_unit                AS valuequantity_unit,
        lab.valuequantity_system              AS valuequantity_system,
        lab.valuequantity_code                AS valuequantity_code,

        lab.valuestring                       AS valuestring,

        lab.dataabsentreason_code             AS dataabsentreason_code,
        lab.dataabsentreason_system           AS dataabsentreason_system,
        lab.dataabsentreason_display          AS dataabsentreason_display,

        lab.status                            AS status,
        lab.specimen_ref                      AS specimen_ref,
        lab.observation_ref                   AS observation_ref,

        lab.observation_encounter_ref         AS lab_observation_encounter_ref,
        link.link_encounter_ref               AS link_encounter_ref,
        'effectivedatetime'                   AS lab_link_method

    FROM date_candidates_links AS link

    JOIN {{ prefix }}__cohort_study_population_lab_base AS lab
        ON lab.observation_ref = link.observation_ref

    WHERE lab.observation_encounter_ref IS NULL
      AND lab.effectivedatetime_day IS NOT NULL
),

union_link AS (
    SELECT
        observation_code, observation_system,
        valuecodeableconcept_code, valuecodeableconcept_display, valuecodeableconcept_system,
        effectivedatetime, effectivedatetime_day,
        interpretation_code, interpretation_system, interpretation_display,
        valuequantity_value, valuequantity_comparator, valuequantity_unit,
        valuequantity_system, valuequantity_code,
        valuestring,
        dataabsentreason_code, dataabsentreason_system, dataabsentreason_display,
        status, specimen_ref, observation_ref,
        lab_observation_encounter_ref, link_encounter_ref, lab_link_method
    FROM by_encounter

    UNION ALL

    SELECT
        observation_code, observation_system,
        valuecodeableconcept_code, valuecodeableconcept_display, valuecodeableconcept_system,
        effectivedatetime, effectivedatetime_day,
        interpretation_code, interpretation_system, interpretation_display,
        valuequantity_value, valuequantity_comparator, valuequantity_unit,
        valuequantity_system, valuequantity_code,
        valuestring,
        dataabsentreason_code, dataabsentreason_system, dataabsentreason_display,
        status, specimen_ref, observation_ref,
        lab_observation_encounter_ref, link_encounter_ref, lab_link_method
    FROM by_effectivedate
),
join_lab AS (
    SELECT  DISTINCT
            union_link.observation_code              AS lab_observation_code,
            union_link.observation_system            AS lab_observation_system,

            union_link.valuecodeableconcept_code     AS lab_concept_code,
            union_link.valuecodeableconcept_display  AS lab_concept_display,
            union_link.valuecodeableconcept_system   AS lab_concept_system,

            union_link.effectivedatetime_day         AS lab_effectivedate,
            union_link.effectivedatetime             AS lab_effectivedatetime,

            union_link.interpretation_code           AS lab_interpretation_code,
            union_link.interpretation_system         AS lab_interpretation_system,
            union_link.interpretation_display        AS lab_interpretation_display,

            union_link.valuequantity_value           AS lab_valuequantity_value,
            union_link.valuequantity_comparator      AS lab_valuequantity_comparator,
            union_link.valuequantity_unit            AS lab_valuequantity_unit,
            union_link.valuequantity_system          AS lab_valuequantity_system,
            union_link.valuequantity_code            AS lab_valuequantity_code,

            union_link.valuestring                   AS lab_valuestring,

            union_link.dataabsentreason_code         AS lab_dataabsentreason_code,
            union_link.dataabsentreason_system       AS lab_dataabsentreason_system,
            union_link.dataabsentreason_display      AS lab_dataabsentreason_display,

            union_link.status                        AS lab_status,
            union_link.specimen_ref                  AS specimen_ref,
            union_link.observation_ref               AS observation_ref,

            -- Audit fields.
            union_link.lab_observation_encounter_ref AS lab_observation_encounter_ref,
            union_link.lab_link_method               AS lab_link_method,

            study_population.*
    FROM    union_link
    JOIN    {{ prefix }}__cohort_study_population AS study_population
    ON      study_population.encounter_ref = union_link.link_encounter_ref
)
-- hydrate lab names with LOINC if display is NULL (often)
SELECT
    CASE
        WHEN join_lab.lab_observation_system = 'http://loinc.org'
        THEN loinc.consumer_name.consumer_name
        ELSE NULL
    END AS lab_observation_display,
        join_lab.*
FROM    join_lab
LEFT    JOIN    loinc.consumer_name
ON      join_lab.lab_observation_code = loinc.consumer_name.loinc_number
;