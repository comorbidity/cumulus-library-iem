--  =====================================================================
--  Link DiagnosticReport to study_population
--
--  PRIORITIES
--    A. encounter_ref   is NOT null
--    B. effectivedatetime / effectiveperiod is NOT null  AND  encounter_ref IS NULL
--
--  TIE-BREAK (exact-start-date)
--    1. encounter starts on the date-mapped day
--    2. narrowest window
--    3. start closest to the date-mapped day
--    4. ordinal
--    5. encounter_ref

--  =====================================================================
CREATE TABLE {{ prefix }}__cohort_study_population_diag AS
WITH
resource_has_encounter_ref AS (
    SELECT  DISTINCT
            diagnosticreport_ref
    FROM    core__diagnosticreport
    WHERE   encounter_ref IS NOT NULL
),

-- Priority A: encounter_ref is NOT null
by_encounter AS (
    SELECT  DISTINCT
            diag.status AS diag_status,
            diag.category_system AS diag_category_system,
            diag.category_code AS diag_category_code,
            diag.category_display AS diag_category_display,
            diag.code_system AS diag_system,
            diag.code_code AS diag_code,
            diag.code_display AS diag_display,
            diag.effectivedatetime_day AS diag_effectivedatetime_day,
            diag.effectiveperiod_start_day AS diag_effectiveperiod_start_day,
            diag.aux_has_text AS aux_has_text,
            diag.result_ref AS result_ref,
            COALESCE(diag.effectivedatetime_day, diag.effectiveperiod_start_day) AS diag_link_day,
            diag.diagnosticreport_ref AS diagnosticreport_ref,
            diag.encounter_ref AS diag_encounter_ref,
            sp.encounter_ref AS link_encounter_ref,
            'encounter_ref' AS diag_link_method
    FROM    {{ prefix }}__cohort_study_population AS sp
    JOIN    core__diagnosticreport AS diag
    ON      sp.encounter_ref = diag.encounter_ref
    WHERE   diag.encounter_ref IS NOT NULL
),

-- Priority B: (effectivedatetime / effectiveperiod is NOT null) and encounter_ref IS NULL
date_candidates AS (
    SELECT  DISTINCT
            diag.diagnosticreport_ref,
            diag.subject_ref,
            COALESCE(diag.effectivedatetime_day, diag.effectiveperiod_start_day) AS candidate_day
    FROM    core__diagnosticreport AS diag
    LEFT JOIN resource_has_encounter_ref AS has_encounter
    ON      diag.diagnosticreport_ref = has_encounter.diagnosticreport_ref
    WHERE   diag.encounter_ref IS NULL
    AND     COALESCE(diag.effectivedatetime_day, diag.effectiveperiod_start_day) IS NOT NULL
    AND     has_encounter.diagnosticreport_ref IS NULL
),

date_candidates_ranked AS (
    SELECT  diag.diagnosticreport_ref,
            sp.encounter_ref AS link_encounter_ref,
            ROW_NUMBER() OVER (
                PARTITION BY diag.diagnosticreport_ref
                ORDER BY
                    -- Tie-Break #1: encounter starts on the date-mapped day
                    CASE
                        WHEN diag.candidate_day = sp.enc_period_start_day
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
                            diag.candidate_day
                        )
                    ) ASC,
                    -- Tie-Break #4: encounter ordinal
                    sp.enc_period_ordinal ASC,
                    -- Tie-Break #5: encounter_ref
                    sp.encounter_ref ASC
            ) AS link_rank
    FROM    date_candidates AS diag
    JOIN    {{ prefix }}__cohort_study_population AS sp
    ON      sp.subject_ref = diag.subject_ref
    AND     diag.candidate_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day_filled
),

date_candidates_links AS (
    SELECT  diagnosticreport_ref,
            link_encounter_ref
    FROM    date_candidates_ranked
    WHERE   link_rank = 1
),

-- Priority B: reattach the chosen encounter to EVERY row of the selected
-- diagnosticreport_ref (preserves multi-row resources, e.g. one row per reaction/result).
by_date AS (
    SELECT  DISTINCT
            diag.status AS diag_status,
            diag.category_system AS diag_category_system,
            diag.category_code AS diag_category_code,
            diag.category_display AS diag_category_display,
            diag.code_system AS diag_system,
            diag.code_code AS diag_code,
            diag.code_display AS diag_display,
            diag.effectivedatetime_day AS diag_effectivedatetime_day,
            diag.effectiveperiod_start_day AS diag_effectiveperiod_start_day,
            diag.aux_has_text AS aux_has_text,
            diag.result_ref AS result_ref,
            COALESCE(diag.effectivedatetime_day, diag.effectiveperiod_start_day) AS diag_link_day,
            diag.diagnosticreport_ref AS diagnosticreport_ref,
            diag.encounter_ref AS diag_encounter_ref,
            link.link_encounter_ref AS link_encounter_ref,
            'effective_date' AS diag_link_method
    FROM    date_candidates_links AS link
    JOIN    core__diagnosticreport AS diag
    ON      diag.diagnosticreport_ref = link.diagnosticreport_ref
    WHERE   diag.encounter_ref IS NULL
      AND   COALESCE(diag.effectivedatetime_day, diag.effectiveperiod_start_day) IS NOT NULL
),

-- by_encounter and by_date are column-aligned, so SELECT * unions positionally.
-- Keep the two branches edited in lockstep.
union_link AS (
    SELECT * FROM by_encounter
    UNION ALL
    SELECT * FROM by_date
)

-- Canonical demographic attach (same as every resource).
, join_diag AS (
    SELECT  DISTINCT
            union_link.diag_status              AS diag_status,
            union_link.diag_category_system     AS diag_category_system,
            union_link.diag_category_code       AS diag_category_code,
            union_link.diag_category_display    AS diag_category_display,
            union_link.diag_system              AS diag_system,
            union_link.diag_code                AS diag_code,
            union_link.diag_display             AS diag_display,
            union_link.diag_effectivedatetime_day AS diag_effectivedatetime_day,
            union_link.diag_effectiveperiod_start_day AS diag_effectiveperiod_start_day,
            union_link.aux_has_text             AS aux_has_text,
            union_link.result_ref               AS result_ref,
            union_link.diag_link_day            AS diag_link_day,
            union_link.diagnosticreport_ref     AS diagnosticreport_ref,
            union_link.diag_encounter_ref       AS diag_encounter_ref,
            union_link.diag_link_method         AS diag_link_method,
            study_population.*
    FROM    union_link
    JOIN    {{ prefix }}__cohort_study_population AS study_population
    ON      study_population.encounter_ref = union_link.link_encounter_ref
),

-- diag-specific enrichment #1: LOINC consumer name + include_diag_category display.
join_diag_display AS (
    SELECT
        COALESCE(valueset.display, join_diag.diag_category_display, 'NONE') AS diag_category_display_best,
        CASE
            WHEN join_diag.diag_system = 'http://loinc.org'
            THEN loinc.consumer_name.consumer_name
            ELSE join_diag.diag_display
        END AS diag_display_best,
        join_diag.*
    FROM    join_diag
    LEFT JOIN loinc.consumer_name
    ON      join_diag.diag_code = loinc.consumer_name.loinc_number
    LEFT JOIN {{ prefix }}__include_diag_category AS valueset
    ON      join_diag.diag_category_code = valueset.code
)

-- diag-specific enrichment #2: result_ref -> core__observation values.
SELECT
        join_diag_display.*,
        obs.interpretation_code      AS obs_interpretation_code,
        obs.interpretation_system    AS obs_interpretation_system,
        obs.interpretation_display   AS obs_interpretation_display,
        obs.valuequantity_value      AS obs_valuequantity_value,
        obs.valuequantity_comparator AS obs_valuequantity_comparator,
        obs.valuequantity_unit       AS obs_valuequantity_unit,
        obs.valuequantity_system     AS obs_valuequantity_system,
        obs.valuequantity_code       AS obs_valuequantity_code,
        obs.valuestring              AS obs_valuestring
FROM    join_diag_display
LEFT JOIN core__observation AS obs
ON      join_diag_display.result_ref = obs.observation_ref
;