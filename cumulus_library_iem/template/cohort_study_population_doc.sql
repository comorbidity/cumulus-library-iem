--  =====================================================================
--  Link DocumentReference to study_population
--
--  PRIORITIES
--    A. encounter_ref   is NOT null
--    B. date is NOT null  AND  encounter_ref IS NULL
--
--  TIE-BREAK (exact-start-date)
--    1. encounter starts on the date-mapped day
--    2. narrowest window
--    3. start closest to the date-mapped day
--    4. ordinal
--    5. encounter_ref
--  =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_doc AS
WITH

-- Any DocumentReference that has native encounter linkage at all.
doc_has_encounter_ref AS (
    SELECT DISTINCT
        documentreference_ref
    FROM core__documentreference
    WHERE encounter_ref IS NOT NULL
),


-- Priority A: encounter_ref is NOT null
by_encounter AS (
    SELECT  DISTINCT
            doc.docstatus               AS docstatus,
            doc.type_code               AS type_code,
            doc.type_display            AS type_display,
            doc.type_system             AS type_system,
            doc.author_day              AS author_day,
            doc."date"                  AS doc_date,
            COALESCE(doc.author_day,DATE(doc."date"))
                                        AS doc_link_day,
            doc.aux_has_text            AS aux_has_text,
            doc.documentreference_ref   AS documentreference_ref,
            doc.encounter_ref           AS doc_encounter_ref,
            sp.encounter_ref            AS link_encounter_ref,
            'encounter_ref'             AS doc_link_method
    FROM    {{ prefix }}__cohort_study_population AS sp
    JOIN    core__documentreference     AS doc
    ON      sp.encounter_ref = doc.encounter_ref
    WHERE   doc.encounter_ref IS NOT NULL
),

-- Priority B: date is NOT null and encounter_ref IS NULL
doc_date_candidates AS (
    SELECT  DISTINCT
            doc.documentreference_ref,
            doc.subject_ref,
            COALESCE(doc.author_day,DATE(doc."date")) AS doc_day
    FROM    core__documentreference AS doc
    LEFT JOIN doc_has_encounter_ref AS has_encounter
    ON      doc.documentreference_ref = has_encounter.documentreference_ref
    WHERE doc.encounter_ref IS NULL
    AND     COALESCE(doc.author_day,DATE(doc."date")) IS NOT NULL
    AND     has_encounter.documentreference_ref IS NULL
),
doc_date_links_ranked AS (
    SELECT  doc.documentreference_ref,
            sp.encounter_ref AS link_encounter_ref,
            ROW_NUMBER() OVER (
                PARTITION BY doc.documentreference_ref
                ORDER BY
                    -- Tie-Break #1: encounter starts on the date-mapped day
                    CASE
                        WHEN doc.doc_day = sp.enc_period_start_day
                        THEN 0 ELSE 1
                    END,
                    -- Tie-Break #2: narrowest window
                    DATE_DIFF(
                        'day',
                        sp.enc_period_start_day,
                        sp.enc_period_end_day_filled
                    ) ASC,
                    -- Tie-Break #3: start closest to the date-mapped day
                    ABS(
                        DATE_DIFF(
                            'day',
                            sp.enc_period_start_day,
                            doc.doc_day
                        )
                    ) ASC,
                    -- Tie-Break #4: encounter ordinal
                    sp.enc_period_ordinal ASC,
                    -- Tie-Break #5: encounter_ref
                    sp.encounter_ref ASC
            ) AS doc_link_rank
    FROM    doc_date_candidates AS doc
    JOIN    {{ prefix }}__cohort_study_population AS sp
    ON      sp.subject_ref = doc.subject_ref
    AND     doc.doc_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day_filled
),
doc_date_links AS (
    SELECT
        documentreference_ref,
        link_encounter_ref
    FROM doc_date_links_ranked
    WHERE doc_link_rank = 1
),
by_date AS (
    SELECT  DISTINCT
            doc.docstatus               AS docstatus,
            doc.type_code               AS type_code,
            doc.type_display            AS type_display,
            doc.type_system             AS type_system,
            doc.author_day              AS author_day,
            doc."date"                  AS doc_date,
            COALESCE(doc.author_day,DATE(doc."date"))
                                        AS doc_link_day,
            doc.aux_has_text            AS aux_has_text,
            doc.documentreference_ref   AS documentreference_ref,
            doc.encounter_ref           AS doc_encounter_ref,
            link.link_encounter_ref     AS link_encounter_ref,
            'document_date'             AS doc_link_method
    FROM    doc_date_links AS link
    JOIN    core__documentreference AS doc
    ON      doc.documentreference_ref = link.documentreference_ref
    WHERE   doc.encounter_ref IS NULL
      AND   COALESCE(doc.author_day,DATE(doc."date")) IS NOT NULL
),
union_link AS (
    SELECT * FROM by_encounter
    UNION ALL
    SELECT * from by_date
)
SELECT DISTINCT
    union_link.docstatus            AS doc_status,
    union_link.type_code            AS doc_type_code,
    union_link.type_display         AS doc_type_display,
    union_link.type_system          AS doc_type_system,
    union_link.author_day           AS doc_author_day,
    union_link.doc_date             AS doc_date,
    union_link.doc_link_day         AS doc_link_day,
    union_link.aux_has_text         AS aux_has_text,
    union_link.documentreference_ref AS documentreference_ref,
    union_link.doc_encounter_ref    AS doc_doc_encounter_ref,
    union_link.doc_link_method      AS doc_link_method,
    study_population.*
FROM union_link
JOIN {{ prefix }}__cohort_study_population AS study_population
    ON study_population.encounter_ref = union_link.link_encounter_ref
;