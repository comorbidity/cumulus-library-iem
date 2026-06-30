--  =====================================================================
--  Link MedicationRequest to study_population
--  priorities:
--    A. encounter_ref maps to a retained study_population encounter
--    B. authoredon present AND encounter_ref is NULL *or* not retained
--       study_population encounter (date-rescue for orphaned requests)
--
--  TIE-BREAK exact-start-date
--    1. encounter starts on the date-mapped day
--    2. narrowest window
--    3. start closest to the date-mapped day
--    4. ordinal
--    5. encounter_ref
--  =====================================================================
CREATE  TABLE   {{ prefix }}__cohort_study_population_rx AS
WITH
-- Priority A: encounter_ref maps to retained study_population encounter
by_encounter AS (
    SELECT  DISTINCT
            rx.status                   AS rx_status,
            rx.category_code            AS rx_category_code,
            rx.category_system          AS rx_category_system,
            rx.category_display         AS rx_category_display,
            rx.medication_code          AS rx_code,
            rx.medication_system        AS rx_system,
            rx.medication_display       AS rx_medication_display,  -- raw hydrated at end
            rx.authoredon               AS rx_authoredon_date,
            rx.medicationrequest_ref    AS medicationrequest_ref,
            rx.subject_ref              AS subject_ref,
            rx.encounter_ref            AS encounter_ref,
            rx.encounter_ref            AS encounter_ref_link,
            'encounter_ref'             AS encounter_ref_link_col
    FROM    {{ prefix }}__cohort_study_population AS sp
    JOIN    core__medicationrequest AS rx
    ON      sp.encounter_ref = rx.encounter_ref
    AND     sp.subject_ref   = rx.subject_ref
    WHERE   rx.encounter_ref IS NOT NULL
),
-- Priority B candidates: authoredon present AND the request's encounter_ref is NOT a
-- retained study_population encounter. The anti-join against cohort_study_population
-- covers BOTH a true-null encounter_ref (never matches) and an encounter_ref pointing
-- at an encounter dropped by the population filters.
date_candidates AS (
    SELECT  DISTINCT
            rx.medicationrequest_ref,
            rx.subject_ref,
            DATE(rx.authoredon)     AS rx_authoredon_day
    FROM    core__medicationrequest AS rx
    LEFT JOIN {{ prefix }}__cohort_study_population AS sp
    ON      rx.encounter_ref = sp.encounter_ref
    AND     rx.subject_ref   = sp.subject_ref
    WHERE   rx.authoredon    IS NOT NULL
    AND     sp.encounter_ref IS     NULL
),
date_candidates_ranked AS (
    SELECT  date_candidates.medicationrequest_ref,
            sp.encounter_ref AS encounter_ref_link,
            date_candidates.subject_ref,
            ROW_NUMBER() OVER (
                PARTITION BY date_candidates.medicationrequest_ref
                ORDER BY
                    -- Tie-Break #1: encounter starts on the date-mapped day
                    CASE WHEN date_candidates.rx_authoredon_day = sp.enc_period_start_day
                         THEN 0 ELSE 1 END,
                    -- Tie-Break #2: narrowest window
                    DATE_DIFF('day', sp.enc_period_start_day, sp.enc_period_end_day_filled) ASC,
                    -- Tie-Break #3: start closest to the date-mapped day
                    ABS(DATE_DIFF('day', sp.enc_period_start_day, date_candidates.rx_authoredon_day)) ASC,
                    -- Tie-Break #4: encounter ordinal
                    sp.enc_period_ordinal ASC,
                    -- Tie-Break #5: encounter_ref
                    sp.encounter_ref ASC
            ) AS rx_link_rank
    FROM    date_candidates
    JOIN    {{ prefix }}__cohort_study_population AS sp
    ON      sp.subject_ref = date_candidates.subject_ref
    AND     date_candidates.rx_authoredon_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day_filled
),
date_candidates_links AS (
    SELECT  medicationrequest_ref,
            subject_ref,
            encounter_ref_link
    FROM    date_candidates_ranked
    WHERE   rx_link_rank = 1
),
by_authoredon AS (
    SELECT  DISTINCT
            rx.status                   AS rx_status,
            rx.category_code            AS rx_category_code,
            rx.category_system          AS rx_category_system,
            rx.category_display         AS rx_category_display,
            rx.medication_code          AS rx_code,
            rx.medication_system        AS rx_system,
            rx.medication_display       AS rx_medication_display,  -- raw hydrated at end
            rx.authoredon               AS rx_authoredon_date,
            rx.medicationrequest_ref    AS medicationrequest_ref,
            rx.subject_ref              AS subject_ref,
            rx.encounter_ref            AS encounter_ref,
            link.encounter_ref_link     AS encounter_ref_link,
            'authoredon'                AS encounter_ref_link_col
    FROM    date_candidates_links   AS link
    JOIN    core__medicationrequest AS rx
    ON      rx.medicationrequest_ref = link.medicationrequest_ref
    AND     rx.subject_ref           = link.subject_ref
    WHERE   rx.authoredon IS NOT NULL
),
union_all AS (
    -- explicit columns guard against positional drift across the UNION
    SELECT rx_status, rx_category_code, rx_category_system, rx_category_display,
           rx_code, rx_system, rx_medication_display, rx_authoredon_date,
           medicationrequest_ref, subject_ref, encounter_ref,
           encounter_ref_link, encounter_ref_link_col
    FROM by_encounter
    UNION ALL
    SELECT rx_status, rx_category_code, rx_category_system, rx_category_display,
           rx_code, rx_system, rx_medication_display, rx_authoredon_date,
           medicationrequest_ref, subject_ref, encounter_ref,
           encounter_ref_link, encounter_ref_link_col
    FROM by_authoredon
)
-- Hydrate medication display ONCE, on the unioned result.
-- NOTE: assumes rxnorm.rxcui_str_longest is unique on (code, system).
-- If not, dedup it first or this re-introduces fan-out.
SELECT  DISTINCT
        union_all.rx_status,
        union_all.rx_category_code,
        union_all.rx_category_system,
        union_all.rx_category_display,
        union_all.rx_code,
        union_all.rx_system,
        COALESCE(NULLIF(TRIM(union_all.rx_medication_display), ''), vocab.display) AS rx_display,
        union_all.rx_authoredon_date,
        union_all.medicationrequest_ref,
        union_all.subject_ref,
        union_all.encounter_ref,
        union_all.encounter_ref_link,
        union_all.encounter_ref_link_col
FROM    union_all
LEFT JOIN rxnorm.rxcui_str_longest AS vocab
ON      union_all.rx_code   = vocab.code
AND     union_all.rx_system = vocab.system
;