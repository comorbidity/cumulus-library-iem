CREATE TABLE {{ prefix }}__cohort_study_period as
WITH
include as
(
    select
        coalesce(date(period_start), date('2000-01-01')) as period_start,
        coalesce(date(period_end),  date(CURRENT_DATE)) as period_end,
        include_history
    from
        {{ prefix }}__include_study_period
),
range as (
    SELECT  DISTINCT
            E.subject_ref,
            E.period_start_day,
            E.period_end_day,
            E.encounter_ref
    FROM
            core__encounter as E,
            include
    WHERE   (E.period_start_day between date(include.period_start) and date(include.period_end))
    AND     (E.period_end_day   between date(include.period_start) and date(include.period_end))
    AND     (E.period_start_day < CURRENT_DATE)
),
history as (
    SELECT  DISTINCT
            E.subject_ref,
            E.period_start_day,
            E.period_end_day,
            E.encounter_ref
    FROM
            core__encounter             as E
    JOIN
            include
      ON    include.include_history
     AND    e.period_start_day < date(include.period_start)
    WHERE   EXISTS  (
            SELECT  1
            FROM    range
            WHERE   range.subject_ref = E.subject_ref)
),
merged as (
    select  *  from range
    UNION ALL
    select  *  from history
),
uniq as (
    SELECT  distinct
            subject_ref,
            period_start_day,
            period_end_day
    from    merged
),
ordinal as (
    SELECT  distinct
            subject_ref,
            period_start_day,
            period_end_day,
            ROW_NUMBER() OVER (
                PARTITION   BY  subject_ref
                ORDER       BY  period_start_day    NULLS LAST,
                                period_end_day      NULLS LAST
            )   AS period_ordinal
    FROM    uniq
)
select  distinct
        ordinal.subject_ref,
        ordinal.period_ordinal,
        ordinal.period_start_day,
        ordinal.period_end_day,
        merged.encounter_ref
from    merged,
        ordinal
where   merged.subject_ref       = ordinal.subject_ref
and     merged.period_start_day  = ordinal.period_start_day
and     merged.period_end_day    = ordinal.period_end_day
;