CREATE      TABLE   {{ prefix }}__cohort_timeline AS
SELECT      DISTINCT
            (wide.{{ encounter_ref }} IS NOT NULL)      AS variable_wide_bool,
            (casedef.{{ encounter_ref }} IS NOT NULL)   AS casedef_bool,
            -- casedef columns from CSV Valueset
            {%- for col in casedef_columns %}
            casedef.{{ col }},
            {%- endfor %}
            --
            casedef.days_since                    AS casedef_days_since,
            casedef.ordinal_since                 AS casedef_ordinal_since,
            casedef.resource_ref                  AS casedef_ref,
            sp.enc_period_start_day	,
            sp.enc_period_end_day   ,
            sp.enc_period_ordinal  	,
            sp.age_at_visit        	,
            sp.gender              	,
            sp.race_display        	,
            sp.ethnicity_display   	,
            sp.enc_class_code      	,
            sp.enc_class_display    ,
            sp.enc_servicetype_code	,
            sp.enc_servicetype_system	,
            sp.enc_servicetype_display	,
            sp.enc_type_code       	,
            sp.enc_type_system     	,
            sp.enc_type_display     ,
            sp.encounter_ref        ,
            sp.subject_ref
FROM        {{ prefix }}__cohort_study_population   AS sp
LEFT JOIN   {{ prefix }}__cohort_casedef            AS casedef
ON          sp.encounter_ref = casedef.{{ encounter_ref }}
LEFT JOIN   {{ prefix }}__cohort_variable_wide    as wide
ON          sp.encounter_ref = wide.{{ encounter_ref }}
;