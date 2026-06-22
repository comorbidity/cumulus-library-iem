CREATE TABLE {{ prefix }}__elastic_union_dx AS
WITH
union_search AS
(
    SELECT  'fhir' as match_type,
            variable,
            subject_ref,
            encounter_ref,
            NULL as note_ref,
            NULL as document_title
    FROM    {{ prefix }}__cohort_variable_union_dx
    UNION ALL
    SELECT  'elastic' as match_type,
            topic as variable,
            subject_ref,
            encounter_ref,
            note_ref,
            document_title
    FROM    {{ prefix }}__elastic_union
),
tabular AS
(
    SELECT      DISTINCT
                (fhir_patient.subject_ref           IS NOT NULL)    AS match_fhir_pat,
                (fhir_encounter.encounter_ref       IS NOT NULL)    AS match_fhir_enc,
                (elastic_patient.subject_ref        IS NOT NULL)    AS match_elastic_pat,
                (elastic_encounter.encounter_ref    IS NOT NULL)    AS match_elastic_enc,
                union_search.variable,
                union_search.document_title,
                union_search.subject_ref,
                union_search.encounter_ref,
                union_search.note_ref
    FROM        union_search
    LEFT JOIN   {{ prefix }}__cohort_variable_union_dx   AS fhir_patient
    ON          union_search.subject_ref        =           fhir_patient.subject_ref
    AND         union_search.variable           =           fhir_patient.variable
    LEFT JOIN   {{ prefix }}__cohort_variable_union_dx   AS fhir_encounter
    ON          union_search.encounter_ref      =           fhir_encounter.encounter_ref
    AND         union_search.variable           =           fhir_encounter.variable
    LEFT JOIN   {{ prefix }}__elastic_union              AS elastic_patient
    ON          union_search.subject_ref        =           elastic_patient.subject_ref
    AND         union_search.variable           =           elastic_patient.topic
    LEFT JOIN   {{ prefix }}__elastic_union              AS elastic_encounter
    ON          union_search.encounter_ref      =           elastic_encounter.encounter_ref
    AND         union_search.variable           =           elastic_encounter.topic
    WHERE       union_search.variable NOT LIKE '%generic%'
),
aggregate as
(
    SELECT
            (match_fhir_pat     OR  match_fhir_enc)     AS match_fhir,
            (match_elastic_pat  OR  match_elastic_enc)  AS match_elastic,
            (match_elastic_pat  OR  match_elastic_enc)  OR
            (match_fhir_pat     OR  match_fhir_enc)     AS match_any,
            (match_elastic_pat  OR  match_elastic_enc)  AND
            (match_fhir_pat     OR  match_fhir_enc)     AS match_both,
            tabular.*
    FROM    tabular
),
hydrate AS
(
    SELECT
            aggregate.*,
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
    FROM    {{ prefix }}__cohort_study_population_enc as enc
    JOIN    aggregate
    ON      enc.encounter_ref = aggregate.encounter_ref
)
SELECT DISTINCT * FROM hydrate
;