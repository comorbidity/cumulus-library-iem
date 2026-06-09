CREATE  TABLE {{ prefix }}__cohort_casedef_dx AS
SELECT  DISTINCT
        {{ casedef_meta }}
        casedef.days_since,
        casedef.ordinal_since,
        casedef.casedef_period,
        variable_union.variable,
        dx.*
FROM    {{ prefix }}__cohort_casedef as casedef
JOIN    {{ prefix }}__cohort_study_population_dx as dx
ON      casedef.encounter_ref = dx.encounter_ref
LEFT JOIN {{ prefix }}__cohort_variable_union AS variable_union
ON      dx.condition_ref = variable_union.resource_ref
;