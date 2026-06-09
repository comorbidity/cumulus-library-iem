-- https://github.com/smart-on-fhir/cumulus-library-ibd-cds/issues/14

create table {{ prefix }}__cohort_study_population_lab as
with join_lab as
(
    select distinct
        observation_code                as lab_observation_code,
        observation_system              as lab_observation_system,
        valuecodeableconcept_code       as lab_concept_code,
        valuecodeableconcept_display    as lab_concept_display,
        valuecodeableconcept_system     as lab_concept_system,
        effectivedatetime_day           as lab_effectivedate,
        interpretation_code             as lab_interpretation_code,
        interpretation_system           as lab_interpretation_system,
        interpretation_display          as lab_interpretation_display,
        valuequantity_value             as lab_valuequantity_value,
        valuequantity_comparator        as lab_valuequantity_comparator,
        valuequantity_unit              as lab_valuequantity_unit,
        valuequantity_system            as lab_valuequantity_system,
        valuequantity_code              as lab_valuequantity_code,
        lab.status                      as lab_status,
        observation_ref,
        study_population.*
    from
        {{ prefix }}__cohort_study_population as study_population,
        core__observation as lab
    where
        lab.category_code = 'laboratory' and
        study_population.encounter_ref = lab.encounter_ref
)
select  case
            when lab_observation_system = 'http://loinc.org'
            then loinc.consumer_name.consumer_name
            else NULL
            end as lab_observation_display,
        join_lab.*
from    join_lab
left join
        loinc.consumer_name on join_lab.lab_observation_code =
        loinc.consumer_name.loinc_number
;


