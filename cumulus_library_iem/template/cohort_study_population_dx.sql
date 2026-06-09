create table {{ prefix }}__cohort_study_population_dx as
select distinct
    DX.category_code        as dx_category_code,
    DX.code                 as dx_code,
    DX.code_display         as dx_display,
    DX.system               as dx_system,
    DX.clinicalstatus_code  as dx_clinical_status,
    DX.verificationstatus_code  as dx_verification_status,
    DX.recordeddate         as dx_recorded_date,
    DX.onsetdatetime        as dx_onset_date,
    DX.condition_ref    as condition_ref,
    study_population.*
from
    {{ prefix }}__cohort_study_population as study_population,
    core__condition as DX
where
    study_population.encounter_ref = DX.encounter_ref
;