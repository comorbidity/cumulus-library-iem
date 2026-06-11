CREATE TABLE {{ prefix }}__elastic_union_dx AS
WITH select_union AS
(
{{ select_union }}
)
SELECT  DISTINCT
        select_union.topic,
        select_union.group_name,
        select_union.note_ref,
        dx.*
FROM    select_union
JOIN    {{ prefix }}__cohort_variable_union_dx as dx
ON      select_union.topic = dx.variable
AND     select_union.encounter_ref = dx.encounter_ref
;