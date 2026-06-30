CREATE  TABLE   {{ prefix }}__cohort_casedef_lab AS
SELECT  DISTINCT
        casedef.days_since,
        casedef.ordinal_since,
        casedef.casedef_period,
        variable_union.variable,
        -- casedef columns from CSV Valueset
        {%- for col in casedef_columns %}
        casedef.{{ col }},
        {%- endfor %}
        --
        lab.*
FROM    {{ prefix }}__cohort_casedef as casedef
JOIN    {{ prefix }}__cohort_study_population_lab as lab
ON      casedef.{{ encounter_ref }} = lab.{{ encounter_ref }}
LEFT JOIN {{ prefix }}__cohort_variable_union AS variable_union
ON      lab.observation_ref = variable_union.resource_ref
;