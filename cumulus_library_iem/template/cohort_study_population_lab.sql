-- =====================================================================
-- {{ prefix }}__cohort_study_population_lab
--
-- Links staged laboratory Observations to in-study encounters with two
-- priorities:
--
--   1. encounter_ref:
--        the Observation carries a native encounter_ref. Join directly to
--        the study population, preserving the original behaviour.
--
--   2. effectivedatetime:
--        the Observation has no native encounter_ref in the staged table,
--        but has effectivedatetime_day. Map it to the same subject's study
--        encounter whose [start, end] window contains the effective date.
--
-- Reads {{ prefix }}__cohort_study_population_lab_base, not
-- core__observation. The native-linkage priority flag (key_has_encounter)
-- was precomputed in the staging scan.
--
-- TIE-BREAK:
--   exact-start-day first.
--
-- Keep this synchronized with rx and dx:
--   1. encounter starts on the effective/date-mapped day,
--   2. narrowest encounter window,
--   3. encounter start closest to the date-mapped day,
--   4. encounter ordinal,
--   5. encounter_ref.
-- =====================================================================

CREATE TABLE {{ prefix }}__cohort_study_population_lab AS

WITH

sp_encounters AS (
    SELECT DISTINCT
        subject_ref,
        encounter_ref,
        enc_period_ordinal,
        enc_period_start_day,
        COALESCE(enc_period_end_day, enc_period_start_day) AS enc_period_end_day
    FROM {{ prefix }}__cohort_study_population
    WHERE encounter_ref IS NOT NULL
),

--
-- Priority 1: Observation has native encounter_ref.
--
by_encounter AS (
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
        sp.encounter_ref                      AS link_encounter_ref,
        'encounter_ref'                       AS lab_link_method

    FROM {{ prefix }}__cohort_study_population_lab_base AS lab

    JOIN sp_encounters AS sp
        ON sp.encounter_ref = lab.observation_encounter_ref

    WHERE lab.observation_encounter_ref IS NOT NULL
),

--
-- Candidate Observations for effectivedatetime fallback: no encounter_ref,
-- present effectivedatetime_day, and no native in-study encounter linkage
-- under the same staged lab_key.
--
lab_effectivedate_candidates AS (
    SELECT DISTINCT
        lab_key,
        subject_ref,
        effectivedatetime_day AS effectivedate_day
    FROM {{ prefix }}__cohort_study_population_lab_base
    WHERE observation_encounter_ref IS NULL
      AND key_has_encounter = 0
      AND effectivedatetime_day IS NOT NULL
),

--
-- Priority 2: map encounter-missing labs to study encounters by subject
-- and effective date within the encounter window.
--
lab_effectivedate_links_ranked AS (
    SELECT
        lab.lab_key,
        sp.encounter_ref AS link_encounter_ref,

        ROW_NUMBER() OVER (
            PARTITION BY lab.lab_key
            ORDER BY
                CASE
                    WHEN lab.effectivedate_day = sp.enc_period_start_day
                    THEN 0 ELSE 1
                END,
                DATE_DIFF(
                    'day',
                    sp.enc_period_start_day,
                    sp.enc_period_end_day
                ) ASC,
                ABS(
                    DATE_DIFF(
                        'day',
                        sp.enc_period_start_day,
                        lab.effectivedate_day
                    )
                ) ASC,
                sp.enc_period_ordinal ASC,
                sp.encounter_ref ASC
        ) AS lab_link_rank

    FROM lab_effectivedate_candidates AS lab

    JOIN sp_encounters AS sp
        ON sp.subject_ref = lab.subject_ref
       AND lab.effectivedate_day BETWEEN sp.enc_period_start_day
                                     AND sp.enc_period_end_day
),

lab_effectivedate_links AS (
    SELECT
        lab_key,
        link_encounter_ref
    FROM lab_effectivedate_links_ranked
    WHERE lab_link_rank = 1
),

--
-- Reattach the chosen encounter to all staged rows for the selected
-- lab_key. Preserves all coding/value rows for the Observation.
--
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

    FROM lab_effectivedate_links AS link

    JOIN {{ prefix }}__cohort_study_population_lab_base AS lab
        ON lab.lab_key = link.lab_key

    WHERE lab.observation_encounter_ref IS NULL
      AND lab.effectivedatetime_day IS NOT NULL
),

lab_links AS (
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
    SELECT DISTINCT
        lab_links.observation_code              AS lab_observation_code,
        lab_links.observation_system            AS lab_observation_system,

        lab_links.valuecodeableconcept_code     AS lab_concept_code,
        lab_links.valuecodeableconcept_display  AS lab_concept_display,
        lab_links.valuecodeableconcept_system   AS lab_concept_system,

        lab_links.effectivedatetime_day         AS lab_effectivedate,
        lab_links.effectivedatetime             AS lab_effectivedatetime,

        lab_links.interpretation_code           AS lab_interpretation_code,
        lab_links.interpretation_system         AS lab_interpretation_system,
        lab_links.interpretation_display        AS lab_interpretation_display,

        lab_links.valuequantity_value           AS lab_valuequantity_value,
        lab_links.valuequantity_comparator      AS lab_valuequantity_comparator,
        lab_links.valuequantity_unit            AS lab_valuequantity_unit,
        lab_links.valuequantity_system          AS lab_valuequantity_system,
        lab_links.valuequantity_code            AS lab_valuequantity_code,

        lab_links.valuestring                   AS lab_valuestring,

        lab_links.dataabsentreason_code         AS lab_dataabsentreason_code,
        lab_links.dataabsentreason_system       AS lab_dataabsentreason_system,
        lab_links.dataabsentreason_display      AS lab_dataabsentreason_display,

        lab_links.status                        AS lab_status,
        lab_links.specimen_ref                  AS specimen_ref,
        lab_links.observation_ref               AS observation_ref,

        -- Audit fields.
        lab_links.lab_observation_encounter_ref AS lab_observation_encounter_ref,
        lab_links.lab_link_method               AS lab_link_method,

        study_population.*

    FROM lab_links

    JOIN {{ prefix }}__cohort_study_population AS study_population
        ON study_population.encounter_ref = lab_links.link_encounter_ref
)

SELECT
    CASE
        WHEN join_lab.lab_observation_system = 'http://loinc.org'
        THEN loinc.consumer_name.consumer_name
        ELSE NULL
    END AS lab_observation_display,

    join_lab.*

FROM join_lab

LEFT JOIN loinc.consumer_name
    ON join_lab.lab_observation_code = loinc.consumer_name.loinc_number

;