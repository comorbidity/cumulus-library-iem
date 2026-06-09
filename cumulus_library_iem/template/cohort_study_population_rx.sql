CREATE TABLE {{ prefix }}__cohort_study_population_rx AS
SELECT DISTINCT
        rx.status               AS rx_status,
        rx.category_code        AS rx_category_code,
        rx.category_system      AS rx_category_system,
        rx.category_display     AS rx_category_display,
        rx.medication_code      AS rx_code,
        rx.medication_system    AS rx_system,
        COALESCE(
            NULLIF(TRIM(rx.medication_display), ''),
            vocab.display)      AS rx_display,
        rx.authoredon           AS rx_authoredon_date,
        rx.medicationrequest_ref AS medicationrequest_ref,
        study_population.*
FROM    {{ prefix }}__cohort_study_population AS study_population
JOIN    core__medicationrequest      AS rx
ON      study_population.encounter_ref = rx.encounter_ref
LEFT JOIN rxnorm.rxcui_str_longest AS vocab
ON      rx.medication_code = vocab.code
AND     rx.medication_system = vocab.system
;