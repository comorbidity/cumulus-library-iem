CREATE TABLE iem__manuscript_timeline AS
WITH
union_search AS
(
    SELECT  'fhir' as match_type,
            variable,
            subject_ref,
            encounter_ref
    FROM    iem__cohort_variable_union_dx
    UNION ALL
    SELECT  'elastic' as match_type,
            topic as variable,
            subject_ref,
            encounter_ref
    FROM    iem__elastic_union
),
tabular AS
(
    SELECT      DISTINCT
                union_search.variable,
                union_search.subject_ref,
                union_search.encounter_ref,
                (fhir.encounter_ref IS NOT NULL)    AS fhir_encounter,
                (elastic.subject_ref IS NOT NULL)   AS elastic_patient
    FROM        union_search
    LEFT JOIN   iem__cohort_variable_union_dx   AS fhir
    ON          union_search.encounter_ref = fhir.encounter_ref
    LEFT JOIN   iem__elastic_union              AS elastic
    ON          union_search.subject_ref = elastic.subject_ref
),
visit AS
(
    SELECT  tabular.*,
            enc.enc_period_start_day,
            enc.enc_period_start_month,
            enc.enc_period_start_year,
            enc.gender,
            enc.race_display,
            enc.age_at_visit,
            enc.age_group,
            enc.enc_class_code,
            enc.enc_servicetype_display,
            enc.enc_type_display
    FROM    iem__cohort_study_population_enc as enc
    JOIN    tabular
    ON      enc.encounter_ref = tabular.encounter_ref
    WHERE   tabular.variable NOT LIKE 'dx_iem_generic%'
)
SELECT * FROM visit


