CREATE  TABLE {{ prefix }}__cohort_casedef AS
WITH
-- casedef matches for encounter_ref
casedef_encounter AS (
    SELECT  DISTINCT
            sp.age_at_visit,
            sp.age_group,
            sp.enc_period_start_day,
            sp.enc_period_ordinal,
            casedef.*
    FROM    {{ prefix }}__cohort_casedef_include as casedef
    JOIN    {{ prefix }}__cohort_study_population as sp
    ON      casedef.encounter_ref = sp.encounter_ref
),
-- rare use of select DISTINCT for query optimization
casedef_subject AS (
    SELECT  DISTINCT
            subject_ref
    FROM    casedef_encounter
),
-- history of subject_ref
longitudinal AS (
    SELECT  sp.enc_period_ordinal,
            sp.enc_period_start_day,
            sp.age_at_visit,
            sp.age_group,
            sp.gender,
            sp.race_display,
            sp.status,
            sp.enc_class_code,
            sp.enc_class_display,
            sp.enc_type_display,
            sp.enc_servicetype_display,
            sp.subject_ref,
            sp.encounter_ref
    FROM    casedef_subject
    JOIN    {{ prefix }}__cohort_study_population as SP
    ON      casedef_subject.subject_ref = sp.subject_ref
),
-- min/max age and periods for subject_ref
calc_duration as (
    SELECT  min(age_at_visit) as age_at_casedef_min,
            max(age_at_visit) as age_at_casedef_max,
            min(enc_period_ordinal)  as enc_period_ordinal_min,
            min(enc_period_start_day) as enc_period_start_day_min,
            subject_ref
    FROM    casedef_encounter
    GROUP BY subject_ref
),
-- days between: *1st* encounter_ref and *this* encounter_ref
calc_days_since as (
    SELECT  date_diff(
                'day',
                DATE(calc_duration.enc_period_start_day_min),
                DATE(longitudinal.enc_period_start_day)) as days_since,
            (longitudinal.enc_period_ordinal - enc_period_ordinal_min) as ordinal_since,
            longitudinal.encounter_ref
    FROM    longitudinal
    JOIN    calc_duration
    ON      longitudinal.subject_ref = calc_duration.subject_ref
),
-- relative period: before, during, or after *1st* casedef match
calc_ordinal AS (
    SELECT  days_since,
            ordinal_since,
            (days_since < 0)    as pre,
            (days_since = 0)    as peri,
            (days_since >= 0)   as peri_post,
            (days_since > 0)    as post,
            calc_days_since.encounter_ref
    FROM    calc_days_since
),
-- Join longitudinal history with calculated values
join_longitudinal AS (
    SELECT  calc_ordinal.days_since,
            calc_ordinal.ordinal_since,
            CASE
            WHEN calc_ordinal.pre  THEN 'pre'
            WHEN calc_ordinal.peri THEN 'peri'
            WHEN calc_ordinal.post THEN 'post'
            ELSE NULL
            END AS casedef_period,
            calc_ordinal.pre,
            calc_ordinal.peri,
            calc_ordinal.peri_post,
            calc_ordinal.post,
            calc_duration.enc_period_ordinal_min,
            longitudinal.enc_period_ordinal,
            calc_duration.enc_period_start_day_min,
            longitudinal.enc_period_start_day,
            calc_duration.age_at_casedef_min,
            calc_duration.age_at_casedef_max,
            longitudinal.age_at_visit,
            longitudinal.age_group,
            longitudinal.gender,
            longitudinal.race_display,
            longitudinal.status,
            longitudinal.enc_class_code,
            longitudinal.enc_class_display,
            longitudinal.enc_type_display,
            longitudinal.enc_servicetype_display,
            longitudinal.subject_ref,
            longitudinal.encounter_ref
    FROM    longitudinal
    JOIN    calc_duration
    ON      longitudinal.subject_ref = calc_duration.subject_ref
    JOIN    calc_ordinal
    ON      longitudinal.encounter_ref = calc_ordinal.encounter_ref
)
SELECT      DISTINCT *
FROM        join_longitudinal
LEFT JOIN   {{ prefix }}__cohort_casedef_include as casedef
USING       (subject_ref, encounter_ref)
;