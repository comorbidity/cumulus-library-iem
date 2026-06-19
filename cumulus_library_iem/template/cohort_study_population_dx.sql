-- =====================================================================
-- {{ prefix }}__cohort_study_population_dx
--
-- Link FHIR Condition to study_population
--
--   1. encounter_ref  : the Condition carries a native encounter_ref.
--
--   2. recordeddate   : the Condition has NO native encounter linkage at
--                       all, but has a `recordeddate`. Map it to the study
--                       encounter (same subject) whose [start, end] window
--                       contains DATE(recordeddate), keeping ONE encounter
--                       per condition_ref (see TIE-BREAK below).
--
-- Conditions with neither encounter_ref nor recordeddate are NOT handled
-- here. this must be addressed separately.

-- Open-ended encounters:
--   * enc_period_end_day_filled (computed upstream in
--     cohort_study_population) treats an open-ended (NULL end) encounter
--     as a single-day window instead of silently dropping the match. This
--     replaces the former inline
--     COALESCE(enc_period_end_day, enc_period_start_day).

-- condition_has_encounter_ref is retained for consistency with the other
-- resources. It enforces the priority rule: a condition_ref with native
-- encounter linkage anywhere is not also recovered through recordeddate.

-- TIE-BREAK (exact-start-day. canonical across all resources):
--   1. an encounter that starts on the recordeddate day,
--   2. the narrowest encounter window,
--   3. the encounter start closest to recordeddate,
--   4. ordinal, 5. encounter_ref for determinism.
-- This matches lab / proc / doc / diag / allergy. Keep rx on the same
-- rule and lock it against the development subset.
-- =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_dx AS

WITH

condition_has_encounter_ref AS (
    SELECT DISTINCT
        condition_ref
    FROM core__condition
    WHERE encounter_ref IS NOT NULL
),

-- Priority 1: Condition has encounter_ref

by_encounter AS (
    SELECT DISTINCT
        dx.category_code            AS category_code,
        dx.code                     AS code,
        dx.code_display             AS code_display,
        dx.system                   AS system,
        dx.clinicalstatus_code      AS clinicalstatus_code,
        dx.verificationstatus_code  AS verificationstatus_code,
        dx.recordeddate             AS recordeddate,
        dx.onsetdatetime            AS onsetdatetime,
        dx.condition_ref            AS condition_ref,
        dx.encounter_ref            AS dx_condition_encounter_ref,
        sp.encounter_ref            AS link_encounter_ref,
        'encounter_ref'             AS dx_link_method

    FROM {{ prefix }}__cohort_study_population AS sp

    JOIN core__condition AS dx
        ON sp.encounter_ref = dx.encounter_ref

    WHERE dx.encounter_ref IS NOT NULL
),

-- fallback: (encounter_ref IS null) and (recordeddate is NOT null)
dx_recordeddate_candidates AS (
    SELECT DISTINCT
        dx.condition_ref,
        dx.subject_ref,
        DATE(dx.recordeddate) AS recordeddate_day

    FROM core__condition AS dx

    LEFT JOIN condition_has_encounter_ref AS has_encounter
        ON dx.condition_ref = has_encounter.condition_ref

    WHERE dx.encounter_ref IS NULL
      AND dx.recordeddate IS NOT NULL
      AND has_encounter.condition_ref IS NULL
),

-- Priority 2: use subject_ref and recordeddate within the encounter date window.

-- TIE-BREAK (exact-start-day. keep identical across resources): when
-- recordeddate falls inside more than one encounter window, prefer
--  1. an encounter that starts on the recordeddate day,
--  2. the narrowest encounter window,
--  3. the encounter start closest to recordeddate,
--  4. ordinal / 5. ref for determinism.


dx_recordeddate_links_ranked AS (
    SELECT
        dx.condition_ref,
        sp.encounter_ref AS link_encounter_ref,

        ROW_NUMBER() OVER (
            PARTITION BY dx.condition_ref
            ORDER BY
                CASE
                    WHEN dx.recordeddate_day = sp.enc_period_start_day
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
                        dx.recordeddate_day
                    )
                ) ASC,
                sp.enc_period_ordinal ASC,
                sp.encounter_ref ASC
        ) AS dx_link_rank

    FROM dx_recordeddate_candidates AS dx

    JOIN {{ prefix }}__cohort_study_population AS sp
        ON sp.subject_ref = dx.subject_ref
       AND dx.recordeddate_day BETWEEN sp.enc_period_start_day
                                   AND sp.enc_period_end_day_filled
),

dx_recordeddate_links AS (
    SELECT
        condition_ref,
        link_encounter_ref
    FROM dx_recordeddate_links_ranked
    WHERE dx_link_rank = 1
),


-- Join the selected recordeddate linkage back to core__condition.
-- preserves all coding rows for the Condition.

by_recordeddate AS (
    SELECT DISTINCT
        dx.category_code            AS category_code,
        dx.code                     AS code,
        dx.code_display             AS code_display,
        dx.system                   AS system,
        dx.clinicalstatus_code      AS clinicalstatus_code,
        dx.verificationstatus_code  AS verificationstatus_code,
        dx.recordeddate             AS recordeddate,
        dx.onsetdatetime            AS onsetdatetime,
        dx.condition_ref            AS condition_ref,
        dx.encounter_ref            AS dx_condition_encounter_ref,
        link.link_encounter_ref     AS link_encounter_ref,
        'recordeddate'              AS dx_link_method

    FROM dx_recordeddate_links AS link

    JOIN core__condition AS dx
        ON dx.condition_ref = link.condition_ref

    WHERE dx.encounter_ref IS NULL
      AND dx.recordeddate IS NOT NULL
),

dx_links AS (
    SELECT
        category_code, code, code_display, system,
        clinicalstatus_code, verificationstatus_code,
        recordeddate, onsetdatetime, condition_ref,
        dx_condition_encounter_ref, link_encounter_ref, dx_link_method
    FROM by_encounter

    UNION ALL

    SELECT
        category_code, code, code_display, system,
        clinicalstatus_code, verificationstatus_code,
        recordeddate, onsetdatetime, condition_ref,
        dx_condition_encounter_ref, link_encounter_ref, dx_link_method
    FROM by_recordeddate
)

SELECT DISTINCT
    dx_links.category_code           AS dx_category_code,
    dx_links.code                    AS dx_code,
    dx_links.code_display            AS dx_display,
    dx_links.system                  AS dx_system,
    dx_links.clinicalstatus_code     AS dx_clinical_status,
    dx_links.verificationstatus_code AS dx_verification_status,
    dx_links.recordeddate            AS dx_recorded_date,
    dx_links.onsetdatetime           AS dx_onset_date,
    dx_links.condition_ref           AS condition_ref,
    dx_links.dx_condition_encounter_ref AS dx_condition_encounter_ref,
    dx_links.dx_link_method          AS dx_link_method,

    study_population.*

FROM dx_links

JOIN {{ prefix }}__cohort_study_population AS study_population
    ON study_population.encounter_ref = dx_links.link_encounter_ref

;