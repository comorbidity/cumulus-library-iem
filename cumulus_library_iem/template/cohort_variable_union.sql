create table {{ prefix }}__cohort_variable_union as
with select_union as
(
{{ select_union }}
)
select distinct
    select_union.variable,
    select_union.code,
    select_union.display,
    select_union.system,
    select_union.resource_ref,
    sp.status,
    sp.age_at_visit,
    sp.age_group,
    sp.gender,
    sp.race_display,
    sp.ethnicity_display,
    sp.enc_period_ordinal,
    sp.enc_period_start_day,
    sp.enc_period_end_day,
    sp.enc_class_code,
    sp.enc_class_display,
    sp.enc_type_system,
    sp.enc_type_code,
    sp.enc_type_display,
    sp.enc_servicetype_system,
    sp.enc_servicetype_code,
    sp.enc_servicetype_display,
    sp.encounter_ref,
    sp.subject_ref
from
    select_union,
    {{ prefix }}__cohort_study_population as sp
where
    select_union.encounter_ref = sp.encounter_ref
;

