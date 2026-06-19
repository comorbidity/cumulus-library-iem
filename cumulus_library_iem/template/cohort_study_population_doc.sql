-- =====================================================================
-- {{ prefix }}__cohort_study_population_doc
--
-- Links DocumentReference resources to in-study encounters with two
-- priorities:
--
--   1. encounter_ref  : the DocumentReference carries a native
--                       encounter_ref. Join straight to the study
--                       population, preserving the original behaviour. A
--                       documentreference_ref that has native linkage
--                       ANYWHERE is handled only here.
--
--   2. document date  : the DocumentReference has NO native encounter
--                       linkage at all, but has a usable date. Map it to
--                       the study encounter (same subject) whose
--                       [start, end] window contains the document day,
--                       keeping ONE encounter per documentreference_ref.
--
-- Document day used for matching:
--   COALESCE(author_day, DATE("date"))
-- author_day is preferred -- it is already day-precision (no DATE()
-- timezone truncation) and reflects when the note was authored. "date"
-- (DocumentReference.date, the reference creation timestamp. a reserved
-- word, hence quoted) is the fallback. Flip the precedence if "date" is
-- the authoritative timing field for your notes.
--
-- Identity key: documentreference_ref (guaranteed non-null, 1:1 with
-- Resource.id), used directly -- no COALESCE(..., id).
--
-- core__documentreference is assumed NOT huge. single-table carry-through
-- like rx / dx / proc. If it is large, apply the lab-style staging table.

-- TIE-BREAK (exact-start-day. canonical across rx / dx / lab / proc / doc):
--   1. encounter starts on the date-mapped day,
--   2. narrowest encounter window,
--   3. encounter start closest to the date-mapped day,
--   4. encounter ordinal, 5. encounter_ref.
-- NOTE: lab / proc / doc use exact-start. rx / dx currently use
-- most-recently-opened. Reconcile all to ONE rule.
-- =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_doc AS
WITH

-- Any DocumentReference that has native encounter linkage at all.
doc_has_encounter_ref AS (
    SELECT DISTINCT
        documentreference_ref
    FROM core__documentreference
    WHERE encounter_ref IS NOT NULL
),

--
-- Priority 1: DocumentReference has native encounter_ref.
--
by_encounter AS (
    SELECT DISTINCT
        doc.docstatus               AS docstatus,
        doc.type_code               AS type_code,
        doc.type_display            AS type_display,
        doc.type_system             AS type_system,
        doc.author_day              AS author_day,
        doc."date"                  AS doc_date,

        COALESCE(
            doc.author_day,
            DATE(doc."date")
        )                           AS doc_link_day,

        doc.aux_has_text            AS aux_has_text,
        doc.documentreference_ref   AS documentreference_ref,

        doc.encounter_ref           AS documentreference_encounter_ref,
        sp.encounter_ref            AS link_encounter_ref,
        'encounter_ref'             AS doc_link_method

    FROM {{ prefix }}__cohort_study_population AS sp

    JOIN core__documentreference AS doc
        ON sp.encounter_ref = doc.encounter_ref

    WHERE doc.encounter_ref IS NOT NULL
),

--
-- Candidate DocumentReferences for date fallback: no encounter_ref, a
-- present document day, and never natively linked anywhere.
--
doc_date_candidates AS (
    SELECT DISTINCT
        doc.documentreference_ref,
        doc.subject_ref,

        COALESCE(
            doc.author_day,
            DATE(doc."date")
        ) AS doc_day

    FROM core__documentreference AS doc

    LEFT JOIN doc_has_encounter_ref AS has_encounter
        ON doc.documentreference_ref = has_encounter.documentreference_ref

    WHERE doc.encounter_ref IS NULL
      AND COALESCE(
            doc.author_day,
            DATE(doc."date")
          ) IS NOT NULL
      AND has_encounter.documentreference_ref IS NULL
),

--
-- Priority 2: map encounter-missing DocumentReferences to study encounters
-- by same subject_ref and document day within the encounter date window.
--
doc_date_links_ranked AS (
    SELECT
        doc.documentreference_ref,
        sp.encounter_ref AS link_encounter_ref,

        ROW_NUMBER() OVER (
            PARTITION BY doc.documentreference_ref
            ORDER BY
                CASE
                    WHEN doc.doc_day = sp.enc_period_start_day
                    THEN 0 ELSE 1
                END,
                DATE_DIFF(
                    'day',
                    sp.enc_period_start_day,
                    sp.enc_period_end_day_filled
                ) ASC,
                ABS(
                    DATE_DIFF(
                        'day',
                        sp.enc_period_start_day,
                        doc.doc_day
                    )
                ) ASC,
                sp.enc_period_ordinal ASC,
                sp.encounter_ref ASC
        ) AS doc_link_rank

    FROM doc_date_candidates AS doc

    JOIN {{ prefix }}__cohort_study_population AS sp
        ON sp.subject_ref = doc.subject_ref
       AND doc.doc_day BETWEEN sp.enc_period_start_day
                           AND sp.enc_period_end_day_filled
),

doc_date_links AS (
    SELECT
        documentreference_ref,
        link_encounter_ref
    FROM doc_date_links_ranked
    WHERE doc_link_rank = 1
),

--
-- Reattach the chosen encounter to all rows of the selected
-- documentreference_ref.
--
by_date AS (
    SELECT DISTINCT
        doc.docstatus               AS docstatus,
        doc.type_code               AS type_code,
        doc.type_display            AS type_display,
        doc.type_system             AS type_system,
        doc.author_day              AS author_day,
        doc."date"                  AS doc_date,

        COALESCE(
            doc.author_day,
            DATE(doc."date")
        )                           AS doc_link_day,

        doc.aux_has_text            AS aux_has_text,
        doc.documentreference_ref   AS documentreference_ref,

        doc.encounter_ref           AS documentreference_encounter_ref,
        link.link_encounter_ref     AS link_encounter_ref,
        'document_date'             AS doc_link_method

    FROM doc_date_links AS link

    JOIN core__documentreference AS doc
        ON doc.documentreference_ref = link.documentreference_ref

    WHERE doc.encounter_ref IS NULL
      AND COALESCE(
            doc.author_day,
            DATE(doc."date")
          ) IS NOT NULL
),

doc_links AS (
    SELECT
        docstatus,
        type_code,
        type_display,
        type_system,
        author_day,
        doc_date,
        doc_link_day,
        aux_has_text,
        documentreference_ref,
        documentreference_encounter_ref,
        link_encounter_ref,
        doc_link_method
    FROM by_encounter

    UNION ALL

    SELECT
        docstatus,
        type_code,
        type_display,
        type_system,
        author_day,
        doc_date,
        doc_link_day,
        aux_has_text,
        documentreference_ref,
        documentreference_encounter_ref,
        link_encounter_ref,
        doc_link_method
    FROM by_date
)

SELECT DISTINCT
    doc_links.docstatus             AS doc_status,
    doc_links.type_code             AS doc_type_code,
    doc_links.type_display          AS doc_type_display,
    doc_links.type_system           AS doc_type_system,
    doc_links.author_day            AS doc_author_day,
    doc_links.doc_date              AS doc_date,
    doc_links.doc_link_day          AS doc_link_day,
    doc_links.aux_has_text          AS aux_has_text,
    doc_links.documentreference_ref AS documentreference_ref,
    doc_links.documentreference_encounter_ref AS doc_documentreference_encounter_ref,
    doc_links.doc_link_method                 AS doc_link_method,
    study_population.*
FROM doc_links
JOIN {{ prefix }}__cohort_study_population AS study_population
    ON study_population.encounter_ref = doc_links.link_encounter_ref
;