CREATE TABLE {{ prefix }}__cohort_study_population_obs_base AS
WITH
study_encounters AS (
    SELECT  DISTINCT
            encounter_ref
    FROM    {{ prefix }}__cohort_study_population
    WHERE   encounter_ref IS NOT NULL
),
study_subject_bounds AS (
    SELECT  subject_ref,
            MIN(enc_period_start_day)       AS min_enc_day,
            MAX(enc_period_end_day_filled)  AS max_enc_day
    FROM    {{ prefix }}__cohort_study_population
    WHERE   encounter_ref IS NOT NULL
    GROUP BY subject_ref
)
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
        obs.observation_ref                   AS observation_ref,

        CASE WHEN enc.encounter_ref IS NOT NULL THEN 1 ELSE 0 END AS obs_has_encounter
FROM        core__observation   AS obs
LEFT JOIN   study_encounters    AS enc
ON          obs.encounter_ref = enc.encounter_ref
LEFT JOIN   study_subject_bounds AS bounds
ON          obs.subject_ref = bounds.subject_ref
WHERE       enc.encounter_ref IS NOT NULL
   OR (
        obs.encounter_ref IS NULL
        AND COALESCE(obs.effectivedatetime_day, DATE(obs.effectivedatetime))
            BETWEEN bounds.min_enc_day AND bounds.max_enc_day
      )
;
