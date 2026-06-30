CREATE  TABLE   {{ prefix }}__cohort_study_population AS
WITH
study_population AS (
    SELECT  DISTINCT
            enc.status,
            enc.age_at_visit,
            valueset_age_group.age_group,
            enc.gender,
            enc.race_display,
            enc.ethnicity_display,
            sp.period_ordinal       AS enc_period_ordinal,
            enc.period_start_day    AS enc_period_start_day,
            enc.period_end_day      AS enc_period_end_day,
            COALESCE(enc.period_end_day, enc.period_start_day)
                                    AS enc_period_end_day_filled,
            enc.class_code          AS enc_class_code,
            enc.class_display       AS enc_class_display,
            enc.servicetype_code    AS enc_servicetype_code,
            enc.servicetype_system  AS enc_servicetype_system,
            enc.servicetype_display AS enc_servicetype_display,
            enc.type_code           AS enc_type_code,
            enc.type_system         AS enc_type_system,
            enc.type_display        AS enc_type_display,
            enc.subject_ref,
            enc.encounter_ref
    from    core__encounter                     AS enc,
            {{ prefix }}__cohort_study_period   AS sp,
            {{ prefix }}__include_gender        AS sex,
            {{ prefix }}__include_age_at_visit  AS age,
            {{ prefix }}__valueset_age_group    AS valueset_age_group
    WHERE   (enc.encounter_ref = sp.encounter_ref)
    AND     (enc.gender = sex.code)
    AND     (enc.age_at_visit BETWEEN age.age_min AND age.age_max)
    AND     (enc.age_at_visit = valueset_age_group.age_at_visit)
),
utilization AS (
    SELECT  COUNT(DISTINCT enc_period_ordinal) AS cnt_period,
            subject_ref
    FROM    study_population
    GROUP BY subject_ref
),
duration AS (
    SELECT  MIN(enc_period_start_day)   AS min_start_day,
            MAX(enc_period_end_day)     AS max_end_day,
            subject_ref
    FROM    study_population
    GROUP BY subject_ref
),
duration_days AS (
    SELECT
            subject_ref,
            duration.min_start_day,
            duration.max_end_day,
            date_diff('day',
            duration.min_start_day,
            duration.max_end_day) AS cnt_days
    FROM    duration
)
SELECT  study_population.*
FROM    study_population,
        utilization,
        duration_days,
        {{ prefix }}__include_utilization AS include
WHERE   study_population.subject_ref = utilization.subject_ref
AND     study_population.subject_ref = duration_days.subject_ref
AND     utilization.cnt_period  BETWEEN include.enc_min  AND include.enc_max
AND     duration_days.cnt_days  BETWEEN include.days_min AND include.days_max
;
