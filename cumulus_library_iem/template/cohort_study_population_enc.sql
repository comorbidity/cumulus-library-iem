create table {{ prefix }}__cohort_study_population_enc as
select distinct
    -- priority
    enc.priority_system     as enc_priority_system,
    enc.priority_code       as enc_priority_code,
    enc.priority_display    as enc_priority_display,

    -- reason for visit
    enc.reasoncode_system   as enc_reasoncode_system,
    enc.reasoncode_code     as enc_reasoncode_code,
    enc.reasoncode_display  as enc_reasoncode_display,

    -- discharged disposition
    enc.dischargedisposition_system     as enc_dischargedisposition_system,
    enc.dischargedisposition_code       as enc_dischargedisposition_code,
    enc.dischargedisposition_display    as enc_dischargedisposition_display,

    -- rollups if desired
    enc.period_start_week   as enc_period_start_week,
    enc.period_start_month  as enc_period_start_month,
    enc.period_start_year   as enc_period_start_year,

    study_population.*
from
    {{ prefix }}__cohort_study_population as study_population,
    core__encounter as enc
where
    study_population.encounter_ref = enc.encounter_ref
;