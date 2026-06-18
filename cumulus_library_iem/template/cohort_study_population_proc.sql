-- =====================================================================
-- {{ prefix }}__cohort_study_population_proc
--
-- Links Procedure resources to in-study encounters with two priorities:
--
--   1. encounter_ref       : the Procedure carries a native encounter_ref.
--                            Join straight to the study population,
--                            preserving the original behaviour. A
--                            procedure_ref that has native linkage ANYWHERE
--                            is handled only here.
--
--   2. performed_date      : the Procedure has NO native encounter linkage
--                            at all, but has a performed date. Map it to
--                            the study encounter (same subject) whose
--                            [start, end] window contains the performed
--                            day, keeping ONE encounter per procedure_ref.
--
-- Procedure.performed[x] is a choice:
--   * performeddatetime: point-in-time performed date
--   * performedperiod_start / performedperiod_end: period-valued procedure
--
-- The performed day used for output and matching is:
--
--   COALESCE(
--       DATE(performeddatetime),
--       DATE(performedperiod_start)
--   )
--
-- This means period-only procedures are anchored at their start date and
-- remain recoverable. performedperiod_end is intentionally not used for
-- encounter attribution unless a future review shows that start is often
-- missing and end is clinically useful.
--
-- The codebase enforces that every core FHIR resource has a non-null true
-- reference column, and Resource.id maps 1:1 to that reference. Therefore
-- this template uses procedure_ref as the Procedure identity key throughout.
--
-- core__procedure is assumed NOT huge, unlike core__observation, so this
-- uses the single-table carry-through pattern like rx / dx. If Procedure
-- becomes large, apply the lab-style staging table pattern instead.
--
-- TIE-BREAK:
-- Keep synchronized across rx / dx / lab / proc:
--   1. encounter starts on the date-mapped day,
--   2. narrowest encounter window,
--   3. encounter start closest to the date-mapped day,
--   4. encounter ordinal,
--   5. encounter_ref.
-- =====================================================================

CREATE TABLE {{ prefix }}__cohort_study_population_proc AS

WITH

-- Any Procedure that has native encounter linkage at all.
-- Used so the performed-date fallback fires only when a procedure_ref
-- lacks encounter linkage entirely.
proc_has_encounter_ref AS (
    SELECT DISTINCT
        procedure_ref
    FROM core__procedure
    WHERE encounter_ref IS NOT NULL
),

--
-- Priority 1:
-- Procedure has native encounter_ref.
--
by_encounter AS (
    SELECT DISTINCT
        proc.category_code      AS category_code,
        proc.category_display   AS category_display,
        proc.category_system    AS category_system,

        proc.status             AS status,

        proc.code_code          AS code_code,
        proc.code_display       AS code_display,
        proc.code_system        AS code_system,

        COALESCE(
            DATE(proc.performeddatetime),
            DATE(proc.performedperiod_start)
        )                       AS performed_day,

        proc.procedure_ref      AS procedure_ref,

        proc.encounter_ref      AS procedure_encounter_ref,
        sp.encounter_ref        AS link_encounter_ref,
        'encounter_ref'         AS proc_link_method

    FROM {{ prefix }}__cohort_study_population AS sp

    JOIN core__procedure AS proc
        ON sp.encounter_ref = proc.encounter_ref

    WHERE proc.encounter_ref IS NOT NULL
),

--
-- Candidate Procedures for performed-date fallback:
-- no encounter_ref, present performed date, and never natively linked
-- anywhere under the same procedure_ref.
--
proc_performed_candidates AS (
    SELECT DISTINCT
        proc.procedure_ref AS procedure_ref,
        proc.subject_ref,

        COALESCE(
            DATE(proc.performeddatetime),
            DATE(proc.performedperiod_start)
        ) AS performed_day

    FROM core__procedure AS proc

    LEFT JOIN proc_has_encounter_ref AS has_encounter
        ON proc.procedure_ref = has_encounter.procedure_ref

    WHERE proc.encounter_ref IS NULL
      AND COALESCE(
            DATE(proc.performeddatetime),
            DATE(proc.performedperiod_start)
          ) IS NOT NULL
      AND has_encounter.procedure_ref IS NULL
),

--
-- Priority 2:
-- Map encounter-missing Procedures to study encounters by same subject_ref
-- and performed_day within the encounter date window.
--
proc_performed_links_ranked AS (
    SELECT
        proc.procedure_ref,
        sp.encounter_ref AS link_encounter_ref,

        ROW_NUMBER() OVER (
            PARTITION BY proc.procedure_ref
            ORDER BY
                CASE
                    WHEN proc.performed_day = sp.enc_period_start_day
                    THEN 0 ELSE 1
                END,

                DATE_DIFF(
                    'day',
                    sp.enc_period_start_day,
                    COALESCE(
                        sp.enc_period_end_day,
                        sp.enc_period_start_day
                    )
                ) ASC,

                ABS(
                    DATE_DIFF(
                        'day',
                        sp.enc_period_start_day,
                        proc.performed_day
                    )
                ) ASC,

                sp.enc_period_ordinal ASC,
                sp.encounter_ref ASC
        ) AS proc_link_rank

    FROM proc_performed_candidates AS proc

    JOIN {{ prefix }}__cohort_study_population AS sp
        ON sp.subject_ref = proc.subject_ref
       AND proc.performed_day BETWEEN sp.enc_period_start_day
                                  AND COALESCE(
                                      sp.enc_period_end_day,
                                      sp.enc_period_start_day
                                  )
),

proc_performed_links AS (
    SELECT
        procedure_ref,
        link_encounter_ref
    FROM proc_performed_links_ranked
    WHERE proc_link_rank = 1
),

--
-- Reattach the chosen encounter to all rows of the selected procedure_ref.
-- This preserves all coding rows for the Procedure.
--
by_performed AS (
    SELECT DISTINCT
        proc.category_code      AS category_code,
        proc.category_display   AS category_display,
        proc.category_system    AS category_system,

        proc.status             AS status,

        proc.code_code          AS code_code,
        proc.code_display       AS code_display,
        proc.code_system        AS code_system,

        COALESCE(
            DATE(proc.performeddatetime),
            DATE(proc.performedperiod_start)
        )                       AS performed_day,

        proc.procedure_ref      AS procedure_ref,

        proc.encounter_ref      AS procedure_encounter_ref,
        link.link_encounter_ref AS link_encounter_ref,
        'performed_date'        AS proc_link_method

    FROM proc_performed_links AS link

    JOIN core__procedure AS proc
        ON proc.procedure_ref = link.procedure_ref

    WHERE proc.encounter_ref IS NULL
      AND COALESCE(
            DATE(proc.performeddatetime),
            DATE(proc.performedperiod_start)
          ) IS NOT NULL
),

proc_links AS (
    SELECT
        category_code,
        category_display,
        category_system,
        status,
        code_code,
        code_display,
        code_system,
        performed_day,
        procedure_ref,
        procedure_encounter_ref,
        link_encounter_ref,
        proc_link_method
    FROM by_encounter

    UNION ALL

    SELECT
        category_code,
        category_display,
        category_system,
        status,
        code_code,
        code_display,
        code_system,
        performed_day,
        procedure_ref,
        procedure_encounter_ref,
        link_encounter_ref,
        proc_link_method
    FROM by_performed
)

SELECT DISTINCT
    proc_links.category_code           AS proc_category_code,
    proc_links.category_display        AS proc_category_display,
    proc_links.category_system         AS proc_category_system,

    proc_links.status                  AS proc_status,

    proc_links.code_code               AS proc_code,
    proc_links.code_display            AS proc_display,
    proc_links.code_system             AS proc_system,

    proc_links.performed_day           AS proc_performed_day,

    proc_links.procedure_ref           AS procedure_ref,

    -- Audit fields.
    proc_links.procedure_encounter_ref AS proc_procedure_encounter_ref,
    proc_links.proc_link_method        AS proc_link_method,

    study_population.*

FROM proc_links

JOIN {{ prefix }}__cohort_study_population AS study_population
    ON study_population.encounter_ref = proc_links.link_encounter_ref

;