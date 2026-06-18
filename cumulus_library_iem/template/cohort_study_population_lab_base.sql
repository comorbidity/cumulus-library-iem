-- =====================================================================
-- {{ prefix }}__cohort_study_population_lab_base   (STAGING)
--
-- Performance-oriented staging table for laboratory Observations.
--
-- core__observation can be huge. This table is the ONLY scan of
-- core__observation for the downstream lab encounter-linkage step.
--
-- It stages only laboratory Observations that can plausibly link to the
-- study population by either:
--
--   1. native encounter_ref:
--        lab.encounter_ref matches an in-study encounter.
--
--   2. effectivedatetime fallback:
--        lab.encounter_ref IS NULL, same subject is in the study
--        population, and effectivedatetime_day falls within that subject's
--        overall in-study encounter date range. The subject-span test
--        cannot drop a true match: any date inside a real encounter window
--        is inside [min, max].
--
-- key_has_encounter is computed in this single pass, so the linkage step
-- never has to re-derive the priority set.
--
-- Build order:
--   cohort_study_population
--   -> cohort_study_population_lab_base
--   -> cohort_study_population_lab
-- =====================================================================

CREATE TABLE {{ prefix }}__cohort_study_population_lab_base AS

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

sp_subject_bounds AS (
    SELECT
        subject_ref,
        MIN(enc_period_start_day) AS min_enc_day,
        MAX(enc_period_end_day) AS max_enc_day
    FROM sp_encounters
    GROUP BY subject_ref
),

lab_candidate AS (
    SELECT
        COALESCE(lab.observation_ref, lab.id) AS lab_key,

        lab.category_code                     AS category_code,
        lab.category_system                   AS category_system,

        lab.status                            AS status,

        lab.observation_code                  AS observation_code,
        lab.observation_system                AS observation_system,

        lab.interpretation_code               AS interpretation_code,
        lab.interpretation_system             AS interpretation_system,
        lab.interpretation_display            AS interpretation_display,

        lab.effectivedatetime                 AS effectivedatetime,
        COALESCE(
            lab.effectivedatetime_day,
            DATE(lab.effectivedatetime)
        )                                     AS effectivedatetime_day,

        lab.valuecodeableconcept_code         AS valuecodeableconcept_code,
        lab.valuecodeableconcept_system       AS valuecodeableconcept_system,
        lab.valuecodeableconcept_display      AS valuecodeableconcept_display,

        lab.valuequantity_value               AS valuequantity_value,
        lab.valuequantity_comparator          AS valuequantity_comparator,
        lab.valuequantity_unit                AS valuequantity_unit,
        lab.valuequantity_system              AS valuequantity_system,
        lab.valuequantity_code                AS valuequantity_code,

        lab.valuestring                       AS valuestring,

        lab.dataabsentreason_code             AS dataabsentreason_code,
        lab.dataabsentreason_system           AS dataabsentreason_system,
        lab.dataabsentreason_display          AS dataabsentreason_display,

        lab.subject_ref                       AS subject_ref,
        lab.encounter_ref                     AS observation_encounter_ref,
        lab.specimen_ref                      AS specimen_ref,
        lab.observation_ref                   AS observation_ref

    FROM core__observation AS lab

    LEFT JOIN sp_encounters AS sp_enc
        ON lab.encounter_ref = sp_enc.encounter_ref

    LEFT JOIN sp_subject_bounds AS bounds
        ON lab.subject_ref = bounds.subject_ref

    WHERE lab.category_code = 'laboratory'
      AND COALESCE(lab.observation_ref, lab.id) IS NOT NULL
      AND (
            -- Native encounter-linked lab already belongs to an in-study encounter.
            sp_enc.encounter_ref IS NOT NULL

            OR

            -- Encounter-missing lab is a date-mapping candidate for an
            -- in-study subject.
            (
                lab.encounter_ref IS NULL
                AND COALESCE(
                    lab.effectivedatetime_day,
                    DATE(lab.effectivedatetime)
                ) BETWEEN bounds.min_enc_day AND bounds.max_enc_day
            )
          )
)

SELECT
    lab_candidate.*,

    -- Native linkage flag within this staged, study-linkable lab universe.
    -- Prevents fallback rows from being double-counted when the same
    -- lab_key already has native in-study encounter linkage.
    --
    -- This reflects IN-STUDY native linkage only, since out-of-study native
    -- rows are not staged. A lab whose sole encounter is out-of-study can
    -- therefore be date-remapped. Deliberate for a study table.
    MAX(
        CASE
            WHEN observation_encounter_ref IS NOT NULL
            THEN 1 ELSE 0
        END
    ) OVER (
        PARTITION BY lab_key
    ) AS key_has_encounter

FROM lab_candidate

;