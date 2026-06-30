CREATE  TABLE   {{ prefix }}__sample_casedef AS
WITH
encounter_casedef AS (
    SELECT  DISTINCT
            etl.group_name,
            casedef.subject_ref,
            casedef.{{ encounter_ref }},
            casedef.days_since,
            casedef.ordinal_since,
            casedef.enc_period_start_day_min,
            population.enc_period_start_day,
            casedef.enc_period_ordinal_min,
            population.enc_period_ordinal
    FROM    etl__completion_encounters      AS etl
    JOIN    {{ prefix }}__cohort_casedef    AS casedef
    ON      casedef.{{ encounter_ref }}   = concat('Encounter/', etl.encounter_id)
    JOIN    {{ prefix }}__cohort_study_population   AS population
    ON      casedef.{{ encounter_ref }}   = population.encounter_ref
),
encounter_doc AS (
    SELECT  DISTINCT
            'documentreference' AS fhir_resource,
            casedef.*,
            CASE
                WHEN    (doc.doc_author_day    IS NOT NULL)
                THEN     doc.doc_author_day
                WHEN    (doc.doc_date          IS NOT NULL)
                THEN     doc.doc_date
                ELSE    casedef.enc_period_start_day
                END AS  sort_by_date,
            doc.doc_author_day          AS note_author_day,
            doc.doc_date                AS note_date,
            doc.doc_type_system         AS note_system,
            doc.doc_type_code           AS note_code,
            doc.doc_type_display        AS note_display,
            doc.documentreference_ref   AS note_ref
    FROM    encounter_casedef           AS casedef
    JOIN    {{ prefix }}__cohort_study_population_doc AS doc
    ON      casedef.{{ encounter_ref }}   = doc.{{ encounter_ref }}
    WHERE   doc.aux_has_text
),
encounter_diag AS (
    SELECT  distinct
            'diagnosticreport' AS fhir_resource,
            casedef.*,
            case
                when   (diag.diag_effectivedatetime_day is NOT null)
                then    diag.diag_effectivedatetime_day
                when   (diag.diag_effectiveperiod_start_day is NOT null)
                then    diag.diag_effectiveperiod_start_day
                else    casedef.enc_period_start_day
                end AS  sort_by_date,
            diag.diag_effectivedatetime_day     AS note_author_day,
            diag.diag_effectiveperiod_start_day AS note_date,
            diag.diag_system                    AS note_system,
            diag.diag_code                      AS note_code,
            diag.diag_display                   AS note_display,
            diag.diagnosticreport_ref           AS note_ref
    FROM    encounter_casedef                   AS casedef
    JOIN    {{ prefix }}__cohort_study_population_diag AS diag
    ON      casedef.{{ encounter_ref }}   = diag.{{ encounter_ref }}
    WHERE   diag.aux_has_text
),
encounter_note as
(
    SELECT * FROM encounter_doc
    UNION ALL
    SELECT * FROM encounter_diag
),
encounter_note_uniq AS
(
    SELECT  DISTINCT
            subject_ref,
            note_ref,
            sort_by_date
    FROM    encounter_note
),
ordered AS (
    SELECT  DISTINCT
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
SELECT  DISTINCT
        encounter_note.*,
        ordered.note_ordinal
FROM    ordered
JOIN    encounter_note
ON      ordered.note_ref = encounter_note.note_ref
;
