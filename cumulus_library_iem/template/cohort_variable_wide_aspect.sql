CREATE  TABLE   {{ prefix }}__cohort_variable_wide_{{ aspect }} AS
SELECT  DISTINCT
{{ select_wide_dict }},
{{ encounter_ref }},
subject_ref
FROM    {{ prefix }}__cohort_variable_union_{{ aspect }}
;