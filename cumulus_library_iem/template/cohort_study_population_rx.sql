-- =====================================================================
-- {{ prefix }}__cohort_study_population_rx
--
-- Links MedicationRequest resources to in-study encounters with two
-- priorities:
--
--   1. encounter_ref  : MedicationRequest encounter_ref is NOT null.
--
--   2. authoredon_date: the resource has NO native encounter linkage at
--                       all, but has an `authoredon` date. Map it to the
--                       study encounter (same subject) whose
--                       [start, end] window contains authoredon, keeping
--                       ONE encounter per request (see TIE-BREAK below).
--
-- Defensive choices (matter only if a medicationrequest_ref can span
-- multiple core__medicationrequest rows, or carry NULLs):
--   * rx_has_encounter_ref prevents a request with mixed linkage from
--     being double-counted across both branches.
--   * enc_period_end_day_filled (computed upstream in
--     cohort_study_population) treats an open-ended (NULL end) encounter
--     as a single-day window instead of silently dropping the match. This
--     replaces the former inline
--     COALESCE(enc_period_end_day, enc_period_start_day).
-- =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_rx AS

WITH

-- MedicationRequests that already have native encounter linkage.
rx_by_encounter_ref AS (
    SELECT DISTINCT
        'encounter_ref' AS rx_join_method,
        rx.encounter_ref AS rx_medicationrequest_encounter_ref,

        rx.status AS rx_status,
        rx.category_code AS rx_category_code,
        rx.category_system AS rx_category_system,
        rx.category_display AS rx_category_display,
        rx.medication_code AS rx_code,
        rx.medication_system AS rx_system,
        COALESCE(
            NULLIF(TRIM(rx.medication_display), ''),
            vocab.display
        ) AS rx_display,
        rx.authoredon AS rx_authoredon_date,
        rx.medicationrequest_ref AS medicationrequest_ref,

        study_population.*

    FROM {{ prefix }}__cohort_study_population AS study_population

    JOIN core__medicationrequest AS rx
        ON study_population.encounter_ref = rx.encounter_ref

    LEFT JOIN rxnorm.rxcui_str_longest AS vocab
        ON rx.medication_code = vocab.code
       AND rx.medication_system = vocab.system
),

-- Any MedicationRequest that has native encounter linkage at all.
-- Used so the authoredOn fallback fires only when a request lacks
-- encounter linkage entirely.
rx_has_encounter_ref AS (
    SELECT DISTINCT
        medicationrequest_ref
    FROM core__medicationrequest
    WHERE encounter_ref IS NOT NULL
),

-- Candidate MedicationRequests for authoredOn fallback.
rx_null_encounter_with_authoredon AS (
    SELECT DISTINCT
        rx.medicationrequest_ref,
        rx.subject_ref,
        DATE(rx.authoredon) AS rx_authoredon_day
    FROM core__medicationrequest AS rx

    LEFT JOIN rx_has_encounter_ref AS has_encounter
        ON rx.medicationrequest_ref = has_encounter.medicationrequest_ref

    WHERE rx.encounter_ref IS NULL
      AND rx.authoredon IS NOT NULL
      AND has_encounter.medicationrequest_ref IS NULL
),

-- Map each encounter-missing MedicationRequest to one best study-population
-- encounter. Subject must match and authoredOn must fall in the encounter
-- date interval.
--
-- TIE-BREAK (the one methodological knob): when authoredOn falls inside
-- more than one encounter window, prefer (1) an encounter that starts on
-- the authoredOn day, (2) the narrowest window, (3) the start closest to
-- authoredOn, then (4) ordinal / (5) ref for determinism. Adjust this
-- ORDER BY if you'd rather attribute to, e.g., the most recently opened
-- admission. Lock the choice against the development subset.
rx_authoredon_match_candidates AS (
    SELECT
        rx.medicationrequest_ref,
        study_population.encounter_ref AS mapped_encounter_ref,

        ROW_NUMBER() OVER (
            PARTITION BY rx.medicationrequest_ref
            ORDER BY
                CASE
                    WHEN rx.rx_authoredon_day = study_population.enc_period_start_day
                    THEN 0 ELSE 1
                END,
                DATE_DIFF(
                    'day',
                    study_population.enc_period_start_day,
                    study_population.enc_period_end_day_filled
                ) ASC,
                ABS(
                    DATE_DIFF(
                        'day',
                        study_population.enc_period_start_day,
                        rx.rx_authoredon_day
                    )
                ) ASC,
                study_population.enc_period_ordinal ASC,
                study_population.encounter_ref ASC
        ) AS rx_join_rank

    FROM rx_null_encounter_with_authoredon AS rx

    JOIN {{ prefix }}__cohort_study_population AS study_population
        ON rx.subject_ref = study_population.subject_ref
       AND rx.rx_authoredon_day BETWEEN study_population.enc_period_start_day
                                    AND study_population.enc_period_end_day_filled
),

rx_authoredon_match AS (
    SELECT
        medicationrequest_ref,
        mapped_encounter_ref
    FROM rx_authoredon_match_candidates
    WHERE rx_join_rank = 1
),

-- MedicationRequests recovered through authoredOn date mapping.
rx_by_authoredon AS (
    SELECT DISTINCT
        'authoredon' AS rx_join_method,
        rx.encounter_ref AS rx_medicationrequest_encounter_ref,

        rx.status AS rx_status,
        rx.category_code AS rx_category_code,
        rx.category_system AS rx_category_system,
        rx.category_display AS rx_category_display,
        rx.medication_code AS rx_code,
        rx.medication_system AS rx_system,
        COALESCE(
            NULLIF(TRIM(rx.medication_display), ''),
            vocab.display
        ) AS rx_display,
        rx.authoredon AS rx_authoredon_date,
        rx.medicationrequest_ref AS medicationrequest_ref,

        study_population.*

    FROM rx_authoredon_match AS match

    JOIN core__medicationrequest AS rx
            ON rx.medicationrequest_ref = match.medicationrequest_ref
       AND rx.encounter_ref IS NULL
       AND rx.authoredon IS NOT NULL

    JOIN {{ prefix }}__cohort_study_population AS study_population
        ON study_population.encounter_ref = match.mapped_encounter_ref

    LEFT JOIN rxnorm.rxcui_str_longest AS vocab
        ON rx.medication_code = vocab.code
       AND rx.medication_system = vocab.system
)

SELECT *
FROM rx_by_encounter_ref

UNION ALL

SELECT *
FROM rx_by_authoredon

;
