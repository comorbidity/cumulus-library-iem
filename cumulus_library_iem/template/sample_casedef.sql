-- nested select DISTINCT was tested here in order to support the PARTITION CLAUSE.
-- this was unexpected to me, but that's what I read. @comorbidity

create TABLE {{ prefix }}__sample_casedef as
WITH
encounter_casedef as (
    SELECT  distinct
            etl.group_name,
            casedef.subject_ref,
            casedef.encounter_ref,
            casedef.days_since,
            casedef.ordinal_since,
            population.enc_period_start_day,
            population.enc_period_ordinal,
            population.enc_class_code,
            population.enc_class_display,
            population.enc_type_display,
            population.enc_servicetype_display
    FROM    etl__completion_encounters          as etl,
            {{ prefix }}__cohort_casedef             as casedef,
            {{ prefix }}__cohort_study_population    as population
    WHERE   casedef.encounter_ref   = population.encounter_ref
    AND     casedef.encounter_ref   = concat('Encounter/', etl.encounter_id)
),
encounter_doc as (
    SELECT  distinct
            'documentreference' as fhir_resource,
            casedef.*,
            case
                when    (doc.doc_author_day    is NOT null)
                then     doc.doc_author_day
                when    (doc.doc_date          is NOT null)
                then     doc.doc_date
                else    doc.enc_period_start_day
                end as  sort_by_date,
            doc.doc_author_day          as note_author_day,
            doc.doc_date                as note_date,
            doc.doc_type_system         as note_system,
            doc.doc_type_code           as note_code,
            doc.doc_type_display        as note_display,
            doc.documentreference_ref   as note_ref
    FROM    encounter_casedef           as casedef,
            {{ prefix }}__cohort_study_population_doc as doc
    WHERE   casedef.encounter_ref   = doc.encounter_ref
    AND     doc.aux_has_text
),
encounter_diag as (
    SELECT  distinct
            'diagnosticreport' as fhir_resource,
            casedef.*,
            case
                when   (diag.diag_effectivedatetime_day is NOT null)
                then    diag.diag_effectivedatetime_day
                when   (diag.diag_effectiveperiod_start_day is NOT null)
                then    diag.diag_effectiveperiod_start_day
                else    diag.enc_period_start_day
                end as  sort_by_date,
            diag.diag_effectivedatetime_day     as note_author_day,
            diag.diag_effectiveperiod_start_day as note_date,
            diag.diag_system                    as note_system,
            diag.diag_code                      as note_code,
            diag.diag_display                   as note_display,
            diag.diagnosticreport_ref           as note_ref
    FROM    encounter_casedef                   as casedef,
            {{ prefix }}__cohort_study_population_diag as diag
    WHERE   casedef.encounter_ref   = diag.encounter_ref
    AND     diag.aux_has_text
),
encounter_note as
(
    select * from encounter_doc
    UNION ALL
    select * from encounter_diag
),
encounter_note_uniq as
(
    SELECT  DISTINCT
            subject_ref,
            note_ref,
            sort_by_date
    FROM    encounter_note
),
ordered as (
    SELECT  distinct
            subject_ref,
            note_ref,
            sort_by_date,
            ROW_NUMBER() OVER (
                PARTITION   BY  subject_ref
                ORDER       BY  sort_by_date,
                                note_ref
            )   AS note_ordinal
    FROM    encounter_note_uniq
)
SELECT  distinct
        encounter_note.*,
        ordered.note_ordinal
FROM    ordered,
        encounter_note
WHERE   ordered.note_ref = encounter_note.note_ref
;
