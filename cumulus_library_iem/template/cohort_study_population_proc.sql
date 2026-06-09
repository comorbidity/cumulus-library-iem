create table {{ prefix }}__cohort_study_population_proc as
select distinct    
    proc.category_code              as proc_category_code,
    proc.category_display           as proc_category_display,
    proc.category_system            as proc_category_system,
    proc.status                     as proc_status,
    proc.code_code                  as proc_code,
    proc.code_display               as proc_display,
    proc.code_system                as proc_system,
    proc.performeddatetime_day      as proc_performed_day,
    proc.procedure_ref,
    study_population.*
from
    {{ prefix }}__cohort_study_population as study_population,
    core__procedure as proc
where
    study_population.encounter_ref = proc.encounter_ref
;
