-- =====================================================================
-- {{ prefix }}__cohort_study_population_diag
--
-- Links DiagnosticReport resources to in-study encounters with two
-- priorities:
--
--   1. encounter_ref  : the DiagnosticReport carries a native
--                       encounter_ref. Join straight to the study
--                       population, preserving the original behaviour. A
--                       diagnosticreport_ref that has native linkage
--                       ANYWHERE is handled only here.
--
--   2. effective_date : the DiagnosticReport has NO native encounter
--                       linkage at all, but has a usable effective day.
--                       Map it to the study encounter, same subject, whose
--                       [start, end] window contains the effective day,
--                       keeping ONE encounter per diagnosticreport_ref.
--
-- DiagnosticReport.effective[x] is a choice:
--   * effectivedatetime
--   * effectiveperiod
--
-- The day used for output and matching is:
--
--   COALESCE(
--       effectivedatetime_day,
--       effectiveperiod_start_day
--   )
--
-- This uses the Cumulus-precomputed _day columns, consistent with the
-- original template and avoids DATE() session-timezone truncation.
--
-- `issued`, the report release timestamp, is intentionally NOT used as an
-- encounter-attribution anchor. Add it as a final COALESCE rung only if a
-- review shows reports with neither effective field are worth recovering.
--
-- Identity key:
--   diagnosticreport_ref
--
-- The codebase enforces that every core FHIR resource has a non-null true
-- reference column, and Resource.id maps 1:1 to that reference. Therefore
-- this template uses diagnosticreport_ref directly throughout.
--
-- A diagnosticreport_ref may span multiple rows, for example one row per
-- result_ref. The carry-through re-join on diagnosticreport_ref preserves
-- those result rows, so the downstream result_ref -> core__observation
-- join still expands correctly.
--
-- This swaps only the encounter-linkage step. The original post-processing
-- is preserved:
--   * LOINC / include_diag_category display enrichment
--   * result_ref -> core__observation value join
--
-- TIE-BREAK:
-- Keep synchronized across rx / dx / lab / proc / doc / diag:
--   1. encounter starts on the date-mapped day,
--   2. narrowest encounter window,
--   3. encounter start closest to the date-mapped day,
--   4. encounter ordinal,
--   5. encounter_ref.
-- =====================================================================

CREATE TABLE {{ prefix }}__cohort_study_population_diag AS

WITH

-- Any DiagnosticReport that has native encounter linkage at all.
-- Used so the effective-date fallback fires only when a
-- diagnosticreport_ref lacks encounter linkage entirely.
diag_has_encounter_ref AS (
    SELECT DISTINCT
        diagnosticreport_ref
    FROM core__diagnosticreport
    WHERE encounter_ref IS NOT NULL
),

--
-- Priority 1:
-- DiagnosticReport has native encounter_ref.
--
by_encounter AS (
    SELECT DISTINCT
        diag.status                    AS diag_status,

        diag.category_system           AS diag_category_system,
        diag.category_code             AS diag_category_code,
        diag.category_display          AS diag_category_display,

        diag.code_system               AS diag_system,
        diag.code_code                 AS diag_code,
        diag.code_display              AS diag_display,

        diag.effectivedatetime_day     AS diag_effectivedatetime_day,
        diag.effectiveperiod_start_day AS diag_effectiveperiod_start_day,

        COALESCE(
            diag.effectivedatetime_day,
            diag.effectiveperiod_start_day
        )                              AS diag_link_day,

        diag.aux_has_text              AS aux_has_text,

        diag.diagnosticreport_ref      AS diagnosticreport_ref,
        diag.result_ref                AS result_ref,

        diag.encounter_ref             AS diag_diagnosticreport_encounter_ref,
        sp.encounter_ref               AS link_encounter_ref,
        'encounter_ref'                AS diag_link_method

    FROM {{ prefix }}__cohort_study_population AS sp

    JOIN core__diagnosticreport AS diag
        ON sp.encounter_ref = diag.encounter_ref

    WHERE diag.encounter_ref IS NOT NULL
),

--
-- Candidate DiagnosticReports for effective-date fallback:
-- no encounter_ref, present effective day, and never natively linked
-- anywhere under the same diagnosticreport_ref.
--
diag_effectivedate_candidates AS (
    SELECT DISTINCT
        diag.diagnosticreport_ref,
        diag.subject_ref,

        COALESCE(
            diag.effectivedatetime_day,
            diag.effectiveperiod_start_day
        ) AS diag_day

    FROM core__diagnosticreport AS diag

    LEFT JOIN diag_has_encounter_ref AS has_encounter
        ON diag.diagnosticreport_ref = has_encounter.diagnosticreport_ref

    WHERE diag.encounter_ref IS NULL
      AND COALESCE(
            diag.effectivedatetime_day,
            diag.effectiveperiod_start_day
          ) IS NOT NULL
      AND has_encounter.diagnosticreport_ref IS NULL
),

--
-- Priority 2:
-- Map encounter-missing DiagnosticReports to study encounters by same
-- subject_ref and effective day within the encounter date window.
--
diag_effectivedate_links_ranked AS (
    SELECT
        diag.diagnosticreport_ref,
        sp.encounter_ref AS link_encounter_ref,

        ROW_NUMBER() OVER (
            PARTITION BY diag.diagnosticreport_ref
            ORDER BY
                CASE
                    WHEN diag.diag_day = sp.enc_period_start_day
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
                        diag.diag_day
                    )
                ) ASC,

                sp.enc_period_ordinal ASC,
                sp.encounter_ref ASC
        ) AS diag_link_rank

    FROM diag_effectivedate_candidates AS diag

    JOIN {{ prefix }}__cohort_study_population AS sp
        ON sp.subject_ref = diag.subject_ref
       AND diag.diag_day BETWEEN sp.enc_period_start_day
                             AND sp.enc_period_end_day_filled
),

diag_effectivedate_links AS (
    SELECT
        diagnosticreport_ref,
        link_encounter_ref
    FROM diag_effectivedate_links_ranked
    WHERE diag_link_rank = 1
),

--
-- Reattach the chosen encounter to all rows of the selected
-- diagnosticreport_ref. This preserves one row per result_ref.
--
by_effectivedate AS (
    SELECT DISTINCT
        diag.status                    AS diag_status,

        diag.category_system           AS diag_category_system,
        diag.category_code             AS diag_category_code,
        diag.category_display          AS diag_category_display,

        diag.code_system               AS diag_system,
        diag.code_code                 AS diag_code,
        diag.code_display              AS diag_display,

        diag.effectivedatetime_day     AS diag_effectivedatetime_day,
        diag.effectiveperiod_start_day AS diag_effectiveperiod_start_day,

        COALESCE(
            diag.effectivedatetime_day,
            diag.effectiveperiod_start_day
        )                              AS diag_link_day,

        diag.aux_has_text              AS aux_has_text,

        diag.diagnosticreport_ref      AS diagnosticreport_ref,
        diag.result_ref                AS result_ref,

        diag.encounter_ref             AS diag_diagnosticreport_encounter_ref,
        link.link_encounter_ref        AS link_encounter_ref,
        'effective_date'               AS diag_link_method

    FROM diag_effectivedate_links AS link

    JOIN core__diagnosticreport AS diag
        ON diag.diagnosticreport_ref = link.diagnosticreport_ref

    WHERE diag.encounter_ref IS NULL
      AND COALESCE(
            diag.effectivedatetime_day,
            diag.effectiveperiod_start_day
          ) IS NOT NULL
),

diag_links AS (
    SELECT
        diag_status,
        diag_category_system,
        diag_category_code,
        diag_category_display,
        diag_system,
        diag_code,
        diag_display,
        diag_effectivedatetime_day,
        diag_effectiveperiod_start_day,
        diag_link_day,
        aux_has_text,
        diagnosticreport_ref,
        result_ref,
        diag_diagnosticreport_encounter_ref,
        link_encounter_ref,
        diag_link_method
    FROM by_encounter

    UNION ALL

    SELECT
        diag_status,
        diag_category_system,
        diag_category_code,
        diag_category_display,
        diag_system,
        diag_code,
        diag_display,
        diag_effectivedatetime_day,
        diag_effectiveperiod_start_day,
        diag_link_day,
        aux_has_text,
        diagnosticreport_ref,
        result_ref,
        diag_diagnosticreport_encounter_ref,
        link_encounter_ref,
        diag_link_method
    FROM by_effectivedate
),

--
-- Attach study population. This replaces the original encounter equi-join.
--
join_diag AS (
    SELECT DISTINCT
        diag_links.diag_status                       AS diag_status,

        diag_links.diag_category_system              AS diag_category_system,
        diag_links.diag_category_code                AS diag_category_code,
        diag_links.diag_category_display             AS diag_category_display,

        diag_links.diag_system                       AS diag_system,
        diag_links.diag_code                         AS diag_code,
        diag_links.diag_display                      AS diag_display,

        diag_links.diag_effectivedatetime_day        AS diag_effectivedatetime_day,
        diag_links.diag_effectiveperiod_start_day    AS diag_effectiveperiod_start_day,

        -- Actual date used for date-window fallback matching.
        diag_links.diag_link_day                     AS diag_link_day,

        diag_links.aux_has_text                      AS aux_has_text,

        diag_links.diagnosticreport_ref              AS diagnosticreport_ref,
        diag_links.result_ref                        AS result_ref,

        -- Audit fields.
        diag_links.diag_diagnosticreport_encounter_ref AS diag_diagnosticreport_encounter_ref,
        diag_links.diag_link_method                  AS diag_link_method,

        study_population.*

    FROM diag_links

    JOIN {{ prefix }}__cohort_study_population AS study_population
        ON study_population.encounter_ref = diag_links.link_encounter_ref
),

--
-- Display enrichment. Preserved from the original template.
--
join_diag_display AS (
    SELECT
        COALESCE(
            valueset.display,
            join_diag.diag_category_display,
            'NONE'
        ) AS diag_category_display_best,

        CASE
            WHEN join_diag.diag_system = 'http://loinc.org'
            THEN loinc.consumer_name.consumer_name
            ELSE join_diag.diag_display
        END AS diag_display_best,

        join_diag.*

    FROM join_diag

    LEFT JOIN loinc.consumer_name
        ON join_diag.diag_code = loinc.consumer_name.loinc_number

    LEFT JOIN {{ prefix }}__include_diag_category AS valueset
        ON join_diag.diag_category_code = valueset.code
)

SELECT DISTINCT
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

FROM join_diag_display

LEFT JOIN core__observation AS obs
    ON join_diag_display.result_ref = obs.observation_ref

;