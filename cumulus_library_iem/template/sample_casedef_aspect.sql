CREATE TABLE {{ prefix }}__sample_casedef_{{ aspect }} AS
SELECT  DISTINCT
        c.subject_ref, c.note_ordinal, c.days_since, c.note_ref, c.group_name
FROM    {{ prefix }}__sample_casedef                        as c
JOIN    {{ prefix }}__cohort_variable_union_{{ aspect }}    as v
        ON c.encounter_ref = v.encounter_ref
;


