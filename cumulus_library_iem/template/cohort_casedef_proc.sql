CREATE  TABLE {{ prefix }}__cohort_casedef_proc as
SELECT  DISTINCT
        {{ casedef_meta }}
        casedef.days_since,
        casedef.ordinal_since,
        casedef.casedef_period,
        proc.*
FROM    {{ prefix }}__cohort_casedef as casedef
JOIN    {{ prefix }}__cohort_study_population_proc as proc
ON      casedef.encounter_ref = proc.encounter_ref
LEFT JOIN {{ prefix }}__cohort_variable_union AS variable_union
ON      proc.procedure_ref = variable_union.resource_ref
;