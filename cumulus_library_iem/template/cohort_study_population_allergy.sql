-- =====================================================================
-- {{ prefix }}__cohort_study_population_allergy
--
-- Links AllergyIntolerance resources to in-study encounters with two
-- priorities:
--
--   1. encounter_ref  : the AllergyIntolerance carries a native
--                       encounter_ref. Join straight to the study
--                       population. An allergyintolerance_ref that has
--                       native linkage ANYWHERE is handled only here.
--
--   2. recordeddate   : the AllergyIntolerance has NO native encounter
--                       linkage at all, but has a recordeddate. Map it to
--                       the study encounter (same subject) whose
--                       [start, end] window contains DATE(recordeddate),
--                       keeping ONE encounter per allergyintolerance_ref.
--
-- Day derivation: DATE(recordeddate). core__allergyintolerance exposes
-- recordeddate as a raw timestamp here; if a precomputed recordeddate_day
-- column exists (as some core tables have), prefer it -- it is day-precision
-- and avoids DATE()'s session-timezone truncation at midnight boundaries.
--
-- Identity key: allergyintolerance_ref (guaranteed non-null, 1:1 with
-- Resource.id), used directly. An allergyintolerance_ref legitimately spans
-- multiple rows -- one per reaction (reaction_row) -- so the carry-through
-- re-join on allergyintolerance_ref preserves every reaction row under the
-- single chosen encounter, just as the diag template preserves result rows.
--
-- core__allergyintolerance is assumed NOT huge; single-table carry-through
-- like rx / dx / proc / doc. If it is large, apply the lab-style staging.
--
-- has_encounter guard retained for consistency with the other resources
-- (inert given non-null refs and single-valued encounter_ref).
--
-- TIE-BREAK (exact-start-day; canonical across all resources):
--   1. encounter starts on the date-mapped day, 2. narrowest window,
--   3. start closest to the date-mapped day, 4. ordinal, 5. encounter_ref.
-- NOTE: lab / proc / doc / diag / allergy use exact-start; rx / dx
-- currently use most-recently-opened. Reconcile all to ONE rule.
-- =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_allergy AS

WITH

-- Any AllergyIntolerance that has native encounter linkage at all.
allergy_has_encounter_ref AS (
    SELECT DISTINCT
        allergyintolerance_ref
    FROM core__allergyintolerance
    WHERE encounter_ref IS NOT NULL
),

--
-- Priority 1: AllergyIntolerance has native encounter_ref.
--
by_encounter AS (
    SELECT DISTINCT
        allergy.clinicalstatus_code              AS allergy_clinical_status,
        allergy.verificationstatus_code          AS allergy_verification_status,
        allergy.type                             AS allergy_type,
        allergy.category                         AS allergy_category,
        allergy.criticality                      AS allergy_criticality,
        allergy.code_code                        AS allergy_code,
        allergy.code_system                      AS allergy_system,
        allergy.code_display                     AS allergy_display,
        allergy.recordeddate                     AS allergy_recorded_date,
        DATE(allergy.recordeddate)               AS allergy_link_day,
        allergy.reaction_row                     AS allergy_reaction_row,
        allergy.reaction_substance_code          AS allergy_reaction_substance_code,
        allergy.reaction_substance_system        AS allergy_reaction_substance_system,
        allergy.reaction_substance_display       AS allergy_reaction_substance_display,
        allergy.reaction_manifestation_code      AS allergy_reaction_manifestation_code,
        allergy.reaction_manifestation_system    AS allergy_reaction_manifestation_system,
        allergy.reaction_manifestation_display   AS allergy_reaction_manifestation_display,
        allergy.reaction_severity                AS allergy_reaction_severity,
        allergy.allergyintolerance_ref           AS allergyintolerance_ref,

        allergy.encounter_ref                    AS allergy_allergyintolerance_encounter_ref,
        sp.encounter_ref                         AS link_encounter_ref,
        'encounter_ref'                          AS allergy_link_method

    FROM {{ prefix }}__cohort_study_population AS sp

    JOIN core__allergyintolerance AS allergy
        ON sp.encounter_ref = allergy.encounter_ref

    WHERE allergy.encounter_ref IS NOT NULL
),

--
-- Candidate AllergyIntolerances for recordeddate fallback: no encounter_ref,
-- a present recordeddate, and never natively linked anywhere.
--
allergy_recordeddate_candidates AS (
    SELECT DISTINCT
        allergy.allergyintolerance_ref,
        allergy.subject_ref,
        DATE(allergy.recordeddate) AS allergy_day

    FROM core__allergyintolerance AS allergy

    LEFT JOIN allergy_has_encounter_ref AS has_encounter
        ON allergy.allergyintolerance_ref = has_encounter.allergyintolerance_ref

    WHERE allergy.encounter_ref IS NULL
      AND allergy.recordeddate IS NOT NULL
      AND has_encounter.allergyintolerance_ref IS NULL
),

--
-- Priority 2: map encounter-missing AllergyIntolerances to study encounters
-- by same subject_ref and recordeddate day within the encounter window.
--
allergy_recordeddate_links_ranked AS (
    SELECT
        allergy.allergyintolerance_ref,
        sp.encounter_ref AS link_encounter_ref,

        ROW_NUMBER() OVER (
            PARTITION BY allergy.allergyintolerance_ref
            ORDER BY
                CASE
                    WHEN allergy.allergy_day = sp.enc_period_start_day
                    THEN 0 ELSE 1
                END,
                DATE_DIFF(
                    'day',
                    sp.enc_period_start_day,
                    COALESCE(sp.enc_period_end_day, sp.enc_period_start_day)
                ) ASC,
                ABS(
                    DATE_DIFF(
                        'day',
                        sp.enc_period_start_day,
                        allergy.allergy_day
                    )
                ) ASC,
                sp.enc_period_ordinal ASC,
                sp.encounter_ref ASC
        ) AS allergy_link_rank

    FROM allergy_recordeddate_candidates AS allergy

    JOIN {{ prefix }}__cohort_study_population AS sp
        ON sp.subject_ref = allergy.subject_ref
       AND allergy.allergy_day BETWEEN sp.enc_period_start_day
                                   AND COALESCE(
                                       sp.enc_period_end_day,
                                       sp.enc_period_start_day
                                   )
),

allergy_recordeddate_links AS (
    SELECT
        allergyintolerance_ref,
        link_encounter_ref
    FROM allergy_recordeddate_links_ranked
    WHERE allergy_link_rank = 1
),

--
-- Reattach the chosen encounter to all rows of the selected
-- allergyintolerance_ref (one row per reaction is preserved).
--
by_recordeddate AS (
    SELECT DISTINCT
        allergy.clinicalstatus_code              AS allergy_clinical_status,
        allergy.verificationstatus_code          AS allergy_verification_status,
        allergy.type                             AS allergy_type,
        allergy.category                         AS allergy_category,
        allergy.criticality                      AS allergy_criticality,
        allergy.code_code                        AS allergy_code,
        allergy.code_system                      AS allergy_system,
        allergy.code_display                     AS allergy_display,
        allergy.recordeddate                     AS allergy_recorded_date,
        DATE(allergy.recordeddate)               AS allergy_link_day,
        allergy.reaction_row                     AS allergy_reaction_row,
        allergy.reaction_substance_code          AS allergy_reaction_substance_code,
        allergy.reaction_substance_system        AS allergy_reaction_substance_system,
        allergy.reaction_substance_display       AS allergy_reaction_substance_display,
        allergy.reaction_manifestation_code      AS allergy_reaction_manifestation_code,
        allergy.reaction_manifestation_system    AS allergy_reaction_manifestation_system,
        allergy.reaction_manifestation_display   AS allergy_reaction_manifestation_display,
        allergy.reaction_severity                AS allergy_reaction_severity,
        allergy.allergyintolerance_ref           AS allergyintolerance_ref,

        allergy.encounter_ref                    AS allergy_allergyintolerance_encounter_ref,
        link.link_encounter_ref                  AS link_encounter_ref,
        'recordeddate'                           AS allergy_link_method

    FROM allergy_recordeddate_links AS link

    JOIN core__allergyintolerance AS allergy
        ON allergy.allergyintolerance_ref = link.allergyintolerance_ref

    WHERE allergy.encounter_ref IS NULL
      AND allergy.recordeddate IS NOT NULL
),

allergy_links AS (
    SELECT
        allergy_clinical_status, allergy_verification_status,
        allergy_type, allergy_category, allergy_criticality,
        allergy_code, allergy_system, allergy_display,
        allergy_recorded_date, allergy_link_day, allergy_reaction_row,
        allergy_reaction_substance_code, allergy_reaction_substance_system, allergy_reaction_substance_display,
        allergy_reaction_manifestation_code, allergy_reaction_manifestation_system, allergy_reaction_manifestation_display,
        allergy_reaction_severity, allergyintolerance_ref,
        allergy_allergyintolerance_encounter_ref, link_encounter_ref, allergy_link_method
    FROM by_encounter

    UNION ALL

    SELECT
        allergy_clinical_status, allergy_verification_status,
        allergy_type, allergy_category, allergy_criticality,
        allergy_code, allergy_system, allergy_display,
        allergy_recorded_date, allergy_link_day, allergy_reaction_row,
        allergy_reaction_substance_code, allergy_reaction_substance_system, allergy_reaction_substance_display,
        allergy_reaction_manifestation_code, allergy_reaction_manifestation_system, allergy_reaction_manifestation_display,
        allergy_reaction_severity, allergyintolerance_ref,
        allergy_allergyintolerance_encounter_ref, link_encounter_ref, allergy_link_method
    FROM by_recordeddate
)

SELECT DISTINCT
    allergy_links.allergy_clinical_status                 AS allergy_clinical_status,
    allergy_links.allergy_verification_status             AS allergy_verification_status,
    allergy_links.allergy_type                            AS allergy_type,
    allergy_links.allergy_category                        AS allergy_category,
    allergy_links.allergy_criticality                     AS allergy_criticality,
    allergy_links.allergy_code                            AS allergy_code,
    allergy_links.allergy_system                          AS allergy_system,
    allergy_links.allergy_display                         AS allergy_display,
    allergy_links.allergy_recorded_date                   AS allergy_recorded_date,

    -- Actual date used for date-window fallback matching.
    allergy_links.allergy_link_day                        AS allergy_link_day,

    allergy_links.allergy_reaction_row                    AS allergy_reaction_row,
    allergy_links.allergy_reaction_substance_code         AS allergy_reaction_substance_code,
    allergy_links.allergy_reaction_substance_system       AS allergy_reaction_substance_system,
    allergy_links.allergy_reaction_substance_display      AS allergy_reaction_substance_display,
    allergy_links.allergy_reaction_manifestation_code     AS allergy_reaction_manifestation_code,
    allergy_links.allergy_reaction_manifestation_system   AS allergy_reaction_manifestation_system,
    allergy_links.allergy_reaction_manifestation_display  AS allergy_reaction_manifestation_display,
    allergy_links.allergy_reaction_severity               AS allergy_reaction_severity,

    allergy_links.allergyintolerance_ref                  AS allergyintolerance_ref,

    -- Audit fields.
    allergy_links.allergy_allergyintolerance_encounter_ref AS allergy_allergyintolerance_encounter_ref,
    allergy_links.allergy_link_method                     AS allergy_link_method,

    study_population.*

FROM allergy_links

JOIN {{ prefix }}__cohort_study_population AS study_population
    ON study_population.encounter_ref = allergy_links.link_encounter_ref

;