create TABLE {{ prefix }}__cohort_study_population_diag as
WITH
join_diag as (
    select  distinct
            diag.status                     as diag_status,
            diag.category_system            as diag_category_system,
            diag.category_code              as diag_category_code,
            diag.category_display           as diag_category_display,
            diag.code_system                as diag_system,
            diag.code_code                  as diag_code,
            diag.code_display               as diag_display,
            diag.effectivedatetime_day      as diag_effectivedatetime_day,
            diag.effectiveperiod_start_day  as diag_effectiveperiod_start_day,
            diag.aux_has_text,
            diag.diagnosticreport_ref       as diagnosticreport_ref,
            diag.result_ref,
    	    study_population.*
	from    {{ prefix }}__cohort_study_population as study_population,
    	    core__diagnosticreport          as diag
    where   study_population.encounter_ref  = diag.encounter_ref
),
join_diag_display as (
    select  coalesce(   valueset.display,
                        diag_category_display, 'NONE') as diag_category_display_best,
            case
                when join_diag.diag_system = 'http://loinc.org'
                then loinc.consumer_name.consumer_name
                else join_diag.diag_display end as diag_display_best,
            join_diag.*
    from    join_diag
    left    join    loinc.consumer_name
            on      join_diag.diag_code = loinc.consumer_name.loinc_number
    left    join    {{ prefix }}__include_diag_category as valueset
            on      join_diag.diag_category_code = valueset.code
)
select      distinct
            join_diag_display.*,
            obs.interpretation_code         as obs_interpretation_code,
            obs.interpretation_system       as obs_interpretation_system,
            obs.interpretation_display      as obs_interpretation_display,
            obs.valuequantity_value         as obs_valuequantity_value,
            obs.valuequantity_comparator    as obs_valuequantity_comparator,
            obs.valuequantity_unit          as obs_valuequantity_unit,
            obs.valuequantity_system        as obs_valuequantity_system,
            obs.valuequantity_code          as obs_valuequantity_code,
            obs.valuestring                 as obs_valuestring
from        join_diag_display
left join   core__observation as obs
        on  join_diag_display.result_ref = obs.observation_ref;
