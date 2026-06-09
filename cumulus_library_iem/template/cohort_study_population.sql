create table {{ prefix }}__cohort_study_population as
WITH
study_population as (
    select  distinct
            E.status,
            E.age_at_visit,
            valueset_age_group.age_group,
            E.gender,
            E.race_display,
            E.ethnicity_display,
            SP.period_ordinal       as enc_period_ordinal,
            E.period_start_day      as enc_period_start_day,
            E.period_end_day        as enc_period_end_day,
            E.class_code            as enc_class_code,
            E.class_display         as enc_class_display,
            E.servicetype_code      as enc_servicetype_code,
            E.servicetype_system    as enc_servicetype_system,
            E.servicetype_display   as enc_servicetype_display,
            E.type_code             as enc_type_code,
            E.type_system           as enc_type_system,
            E.type_display          as enc_type_display,
            E.subject_ref,
            E.encounter_ref
    from    core__encounter                     as E,
            {{ prefix }}__cohort_study_period        as SP,
            {{ prefix }}__include_gender             as G,
            {{ prefix }}__include_age_at_visit       as age,
            {{ prefix }}__valueset_age_group         as valueset_age_group
    where   (E.encounter_ref = SP.encounter_ref)  and
            (E.gender = G.code)                   and
            (E.age_at_visit between age.age_min and age.age_max) and
            (E.age_at_visit = valueset_age_group.age_at_visit)
),
utilization as (
    select  count(distinct enc_period_ordinal) as cnt_period,
            subject_ref
    from    study_population
    group by subject_ref
),
duration as (
    select  min(enc_period_start_day)   as min_start_day,
            max(enc_period_end_day)     as max_end_day,
            subject_ref
    from    study_population
    group by subject_ref
),
duration_days as (
    select
            subject_ref,
            duration.min_start_day,
            duration.max_end_day,
            date_diff('day',
            duration.min_start_day,
            duration.max_end_day) as cnt_days
    from    duration
)
select
        study_population.*
from
        study_population,
        utilization,
        duration_days,
        {{ prefix }}__include_utilization as include
where
        study_population.subject_ref = utilization.subject_ref
and     study_population.subject_ref = duration_days.subject_ref
and     utilization.cnt_period  between include.enc_min  and include.enc_max
and     duration_days.cnt_days  between include.days_min and include.days_max
;
