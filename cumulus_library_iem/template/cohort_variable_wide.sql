CREATE TABLE {{ prefix }}__cohort_variable_wide AS
with
select_wide_bool AS
(
    SELECT
            {{ select_wide_bool }},
            encounter_ref
    FROM    {{ prefix }}__cohort_variable_union
),
select_wide_any AS
(
    SELECT
            {{ select_wide_any }},
            encounter_ref
    FROM    select_wide_bool
    GROUP BY encounter_ref
)
SELECT  DISTINCT
        select_wide_any.*
FROM    select_wide_any
;