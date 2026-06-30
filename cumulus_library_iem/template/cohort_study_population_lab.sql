-- Dependency tree:
--  cohort_study_period
--  cohort_study_population
--  cohort_study_population_obs_base
--  cohort_study_population_lab_base
--  cohort_study_population_lab (this table)
--  =====================================================================
--  Link Observation laboratory to study_population
--  priorities:

--  A. encounter_ref maps to a retained study_population encounter
--  B. effectivedatetime present AND obs_has_encounter = 0 (encounter_ref is NULL
--     *or* not retained study_population encounter) -- date-rescue for orphans.
--     Orphan admission (incl. dropped-encounter labs) is handled upstream in
--     cohort_study_population_obs_base: here we just route obs_has_encounter = 0.

-- TIE-BREAK exact-start-date
--  1. encounter starts on the date-mapped day
--  2. narrowest window
--  3. start closest to the date-mapped day
--  4. ordinal
--  5. encounter_ref
-- =====================================================================
CREATE  TABLE   {{ prefix }}__cohort_study_population_lab AS
WITH
has_encounter AS (
    SELECT  DISTINCT
            subject_ref,
            encounter_ref,
            enc_period_ordinal,
            enc_period_start_day,
            enc_period_end_day_filled
    FROM    {{ prefix }}__cohort_study_population
    WHERE   encounter_ref IS NOT NULL
),
-- Priority A: encounter_ref maps to retained study_population encounter
by_encounter AS (
    SELECT  lab.lab_observation_code,
            lab.lab_observation_system,
            lab.lab_concept_code,
            lab.lab_concept_display,
            lab.lab_concept_system,

            lab.lab_effectivedate,
            lab.lab_effectivedate_day,

            lab.lab_interpretation_code,
            lab.lab_interpretation_system,
            lab.lab_interpretation_display,

            lab.lab_valuequantity_value,
            lab.lab_valuequantity_comparator,
            lab.lab_valuequantity_unit,
            lab.lab_valuequantity_system,
            lab.lab_valuequantity_code,

            lab.lab_valuestring,
            lab.lab_dataabsentreason,
            lab.lab_status,

            lab.observation_ref,
            lab.specimen_ref,

            lab.subject_ref,
            lab.encounter_ref,
            lab.encounter_ref AS encounter_ref_link,
            'encounter_ref'   AS encounter_ref_link_col

    FROM    {{ prefix }}__cohort_study_population_lab_base AS lab
    JOIN    has_encounter
    ON      has_encounter.encounter_ref = lab.encounter_ref
    AND     has_encounter.subject_ref   = lab.subject_ref
    WHERE   lab.encounter_ref IS NOT NULL
),

-- Priority B candidates: effectivedatetime present AND the lab is NOT on retained
-- study_population encounter. obs_has_encounter = 0 is the anti-join sentinel set in obs_base
date_candidates AS (
    SELECT  DISTINCT
            observation_ref,
            subject_ref,
            lab_effectivedate_day
    FROM    {{ prefix }}__cohort_study_population_lab_base
    WHERE   obs_has_encounter = 0
    AND     lab_effectivedate_day   IS NOT  NULL
),
date_candidates_ranked AS (
    SELECT  lab.observation_ref,
            sp.encounter_ref AS encounter_ref_link,

            ROW_NUMBER() OVER (
                PARTITION BY lab.observation_ref
                ORDER BY
                    -- Tie-Break #1: encounter starts on the date-mapped day
                    CASE
                        WHEN lab.lab_effectivedate_day = sp.enc_period_start_day
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
                            lab.lab_effectivedate_day
                        )
                    ) ASC,
                    -- Tie-Break #4: encounter ordinal
                    sp.enc_period_ordinal ASC,
                    -- Tie-Break #5: encounter_ref
                    sp.encounter_ref ASC
            ) AS lab_link_rank
    FROM    date_candidates AS lab
    JOIN    has_encounter AS sp
    ON      sp.subject_ref = lab.subject_ref
    AND     lab.lab_effectivedate_day BETWEEN sp.enc_period_start_day AND sp.enc_period_end_day_filled
),
date_candidates_links AS (
    SELECT
        observation_ref,
        encounter_ref_link
    FROM date_candidates_ranked
    WHERE lab_link_rank = 1
),
by_effectivedate AS (
    SELECT  lab.lab_observation_code,
            lab.lab_observation_system,
            lab.lab_concept_code,
            lab.lab_concept_display,
            lab.lab_concept_system,

            lab.lab_effectivedate,
            lab.lab_effectivedate_day,

            lab.lab_interpretation_code,
            lab.lab_interpretation_system,
            lab.lab_interpretation_display,

            lab.lab_valuequantity_value,
            lab.lab_valuequantity_comparator,
            lab.lab_valuequantity_unit,
            lab.lab_valuequantity_system,
            lab.lab_valuequantity_code,
            lab.lab_valuestring,
            lab.lab_dataabsentreason,
            lab.lab_status,

            lab.observation_ref,
            lab.specimen_ref,

            lab.subject_ref,
            lab.encounter_ref,
            link.encounter_ref_link AS encounter_ref_link,
            'effectivedatetime'     AS encounter_ref_link_col
    FROM    date_candidates_links   AS link
    JOIN    {{ prefix }}__cohort_study_population_lab_base AS lab
    ON      lab.observation_ref = link.observation_ref
    WHERE   lab.lab_effectivedate_day   IS NOT  NULL
),
union_link AS (
    SELECT * FROM by_encounter
    UNION ALL
    SELECT * FROM by_effectivedate
),
hydrate as (
    SELECT
        CASE
            WHEN union_link.lab_observation_system = 'http://loinc.org'
            THEN loinc.consumer_name.consumer_name
            ELSE NULL
        END AS lab_observation_display,
            union_link.*
    FROM    union_link
    LEFT    JOIN    loinc.consumer_name
    ON      union_link.lab_observation_code = loinc.consumer_name.loinc_number
)
SELECT  DISTINCT
        hydrate.*
FROM    hydrate
;
