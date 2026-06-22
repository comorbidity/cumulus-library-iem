--  =====================================================================
--  Link MedicationRequest to study_population
--  priorities:

--  A. encounter_ref    is NOT null
--  B. authoredon       is NOT null and encounter_ref IS NULL

-- TIE-BREAK exact-start-date
--  1. encounter starts on the date-mapped day
--  2. narrowest window
--  3. start closest to the date-mapped day
--  4. ordinal
--  5. encounter_ref
-- =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_rx AS
WITH
resource_has_encounter_ref AS (
    SELECT  DISTINCT
            medicationrequest_ref
    FROM    core__medicationrequest
    WHERE   encounter_ref IS NOT NULL
),
-- Priority A: encounter_ref is NOT null
by_encounter AS (
    SELECT  DISTINCT
            'encounter_ref'             AS rx_link_method,
            rx.encounter_ref            AS rx_encounter_ref,
            rx.status                   AS rx_status,
            rx.category_code            AS rx_category_code,
            rx.category_system          AS rx_category_system,
            rx.category_display         AS rx_category_display,
            rx.medication_code          AS rx_code,
            rx.medication_system        AS rx_system,
            COALESCE(NULLIF(TRIM(rx.medication_display), ''), vocab.display) AS rx_display,
            rx.authoredon               AS rx_authoredon_date,
            rx.medicationrequest_ref    AS medicationrequest_ref,
            sp.*
    FROM    {{ prefix }}__cohort_study_population AS sp
    JOIN    core__medicationrequest     AS rx
    ON      sp.encounter_ref = rx.encounter_ref
    LEFT JOIN rxnorm.rxcui_str_longest  AS vocab
    ON      rx.medication_code = vocab.code
    AND     rx.medication_system = vocab.system
),
-- Priority B: authoredon is NOT null and encounter_ref IS NULL
date_candidates AS (
    SELECT  DISTINCT
            rx.medicationrequest_ref,
            rx.subject_ref,
            DATE(rx.authoredon)             AS rx_authoredon_day
    FROM    core__medicationrequest         AS rx
    LEFT JOIN resource_has_encounter_ref    AS has_encounter
    ON      rx.medicationrequest_ref = has_encounter.medicationrequest_ref
    WHERE   rx.encounter_ref    IS      NULL
      AND   rx.authoredon       IS NOT  NULL
      AND   has_encounter.medicationrequest_ref IS NULL
),
date_candidates_ranked AS (
    SELECT  rx.medicationrequest_ref,
            sp.encounter_ref AS link_encounter_ref,
            ROW_NUMBER() OVER (
                PARTITION BY rx.medicationrequest_ref
                ORDER BY
                    -- Tie-Break #1: encounter starts on the date-mapped day
                    CASE
                        WHEN rx.rx_authoredon_day = sp.enc_period_start_day
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
                            rx.rx_authoredon_day
                        )
                    ) ASC,
                    -- Tie-Break #4: encounter ordinal
                    sp.enc_period_ordinal ASC,
                    -- Tie-Break #5: encounter_ref
                    sp.encounter_ref ASC
            ) AS rx_link_rank
    FROM    date_candidates AS rx
    JOIN    {{ prefix }}__cohort_study_population AS sp
    ON      rx.subject_ref = sp.subject_ref
    AND     rx.rx_authoredon_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day_filled
),

date_candidates_links AS (
    SELECT  medicationrequest_ref,
            link_encounter_ref
    FROM    date_candidates_ranked
    WHERE   rx_link_rank = 1
),

-- MedicationRequests recovered through authoredOn date mapping.
by_authoredon AS (
    SELECT DISTINCT
        'authoredon'                AS rx_link_method,
        rx.encounter_ref            AS rx_encounter_ref,
        rx.status                   AS rx_status,
        rx.category_code            AS rx_category_code,
        rx.category_system          AS rx_category_system,
        rx.category_display         AS rx_category_display,
        rx.medication_code          AS rx_code,
        rx.medication_system        AS rx_system,
        COALESCE(NULLIF(TRIM(rx.medication_display), ''),vocab.display)
                                    AS rx_display,
        rx.authoredon               AS rx_authoredon_date,
        rx.medicationrequest_ref    AS medicationrequest_ref,
        sp.*
    FROM    date_candidates_links   AS link
    JOIN    core__medicationrequest AS rx
    ON      rx.medicationrequest_ref = link.medicationrequest_ref
    AND     rx.encounter_ref    IS      NULL
    AND     rx.authoredon       IS NOT  NULL
    JOIN    {{ prefix }}__cohort_study_population AS sp
    ON      sp.encounter_ref = link.link_encounter_ref
    LEFT JOIN rxnorm.rxcui_str_longest AS vocab
    ON      rx.medication_code = vocab.code
    AND     rx.medication_system = vocab.system
)
SELECT * FROM by_encounter
UNION ALL
SELECT * FROM by_authoredon
;
