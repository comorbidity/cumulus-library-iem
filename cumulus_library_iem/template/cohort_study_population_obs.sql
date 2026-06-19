-- =====================================================================
-- {{ prefix }}__cohort_study_population_obs   (STAGING)
--
-- Performance-oriented staging table for Observations (ALL categories).
--
-- Generic sibling of {{ prefix }}__cohort_study_population_lab_base. The
-- ONLY structural difference is that this table does NOT restrict to
-- category_code = laboratory it stages every Observation category
-- (vital-signs, laboratory, survey, imaging, social-history, ...) that
-- can plausibly link to the study population. category_code /
-- category_system are still projected, so a downstream step can filter by
-- category -- only the WHERE-clause restriction is removed.
--
-- core__observation can be huge, and without the laboratory filter this
-- scans even more of it, so this table is intended to be the ONLY scan of
-- core__observation for the downstream obs encounter-linkage step.
--
-- It stages only Observations that can plausibly link to the study
-- population by either:
--
--   1. native encounter_ref:
--        obs.encounter_ref matches an in-study encounter.
--
--   2. effectivedatetime fallback:
--        obs.encounter_ref IS NULL, same subject is in the study
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
--   -> cohort_study_population_obs        (this table all categories)
--   -> cohort_study_population_lab_base   (laboratory filter over obs)
--   -> cohort_study_population_lab        (laboratory encounter linkage)
-- =====================================================================

CREATE TABLE {{ prefix }}__cohort_study_population_obs AS

WITH

sp_encounters AS (
    SELECT DISTINCT
        subject_ref,
        encounter_ref,
        enc_period_ordinal,
        enc_period_start_day,
        enc_period_end_day_filled AS enc_period_end_day
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

obs_candidate AS (
    SELECT
        obs.category_code                     AS category_code,
        obs.category_system                   AS category_system,

        obs.status                            AS status,
        obs.observation_code                  AS observation_code,
        obs.observation_system                AS observation_system,

        obs.interpretation_code               AS interpretation_code,
        obs.interpretation_system             AS interpretation_system,
        obs.interpretation_display            AS interpretation_display,

        obs.effectivedatetime                 AS effectivedatetime,
        COALESCE(
            obs.effectivedatetime_day,
            DATE(obs.effectivedatetime)
        )                                     AS effectivedatetime_day,

        obs.valuecodeableconcept_code         AS valuecodeableconcept_code,
        obs.valuecodeableconcept_system       AS valuecodeableconcept_system,
        obs.valuecodeableconcept_display      AS valuecodeableconcept_display,

        obs.valuequantity_value               AS valuequantity_value,
        obs.valuequantity_comparator          AS valuequantity_comparator,
        obs.valuequantity_unit                AS valuequantity_unit,
        obs.valuequantity_system              AS valuequantity_system,
        obs.valuequantity_code                AS valuequantity_code,

        obs.valuestring                       AS valuestring,

        obs.dataabsentreason_code             AS dataabsentreason_code,
        obs.dataabsentreason_system           AS dataabsentreason_system,
        obs.dataabsentreason_display          AS dataabsentreason_display,

        obs.subject_ref                       AS subject_ref,
        obs.encounter_ref                     AS observation_encounter_ref,
        obs.specimen_ref                      AS specimen_ref,
        obs.observation_ref                   AS observation_ref

    FROM core__observation AS obs

    LEFT JOIN sp_encounters AS sp_enc
        ON obs.encounter_ref = sp_enc.encounter_ref

    LEFT JOIN sp_subject_bounds AS bounds
        ON obs.subject_ref = bounds.subject_ref

    WHERE (
            -- Native encounter-linked obs already belongs to an in-study encounter.
            sp_enc.encounter_ref IS NOT NULL

            OR

            -- Encounter-missing obs is a date-mapping candidate for an
            -- in-study subject.
            (
                obs.encounter_ref IS NULL
                AND COALESCE(
                    obs.effectivedatetime_day,
                    DATE(obs.effectivedatetime)
                ) BETWEEN bounds.min_enc_day AND bounds.max_enc_day
            )
          )
)

SELECT
    obs_candidate.*,

    -- Native linkage flag within this staged, study-linkable obs universe.
    -- Prevents fallback rows from being double-counted when the same
    -- observation_ref already has native in-study encounter linkage.
    --
    -- This reflects IN-STUDY native linkage only, since out-of-study native
    -- rows are not staged. An obs whose sole encounter is out-of-study can
    -- therefore be date-remapped. Deliberate for a study table.
    MAX(
        CASE
            WHEN observation_encounter_ref IS NOT NULL
            THEN 1 ELSE 0
        END
    ) OVER (
        PARTITION BY observation_ref
    ) AS key_has_encounter

FROM obs_candidate
;
