CREATE  TABLE   {{ prefix }}__cohort_study_population_lab_base AS
SELECT  DISTINCT
        obs.observation_code                AS lab_observation_code,
        obs.observation_system              AS lab_observation_system,

        obs.valuecodeableconcept_code       AS lab_concept_code,
        obs.valuecodeableconcept_display    AS lab_concept_display,
        obs.valuecodeableconcept_system     AS lab_concept_system,

        obs.effectivedatetime               AS lab_effectivedate,
        obs.effectivedatetime_day           AS lab_effectivedate_day,

        obs.interpretation_code             AS lab_interpretation_code,
        obs.interpretation_system           AS lab_interpretation_system,
        obs.interpretation_display          AS lab_interpretation_display,

        obs.valuequantity_value             AS lab_valuequantity_value,
        obs.valuequantity_comparator        AS lab_valuequantity_comparator,
        obs.valuequantity_unit              AS lab_valuequantity_unit,
        obs.valuequantity_system            AS lab_valuequantity_system,
        obs.valuequantity_code              AS lab_valuequantity_code,

        obs.valuestring                     AS lab_valuestring,
        obs.dataabsentreason_code           AS lab_dataabsentreason,

        obs.status                          AS lab_status,
        obs.subject_ref                     AS subject_ref,
        obs.observation_ref                 AS observation_ref,
        obs.specimen_ref                    AS specimen_ref,
        obs.encounter_ref                   AS encounter_ref,
        obs.obs_has_encounter               as obs_has_encounter

FROM    {{ prefix }}__cohort_study_population_obs_base AS obs
WHERE   category_code = 'laboratory'
;