-- =====================================================================
-- Staged build of {{ prefix }}__cohort_study_population_obs
--
-- core__observation can easily be ~1e9 (1 BILLION) rows.
-- That scan is paid EXACTLY ONCE here

-- Build order:
--   {{ prefix }}__cohort_study_population
--   -> {{ prefix }}__obs_temp_enc
--   -> {{ prefix }}__cohort_study_population_temp_subject
--   -> {{ prefix }}__cohort_study_population_obs
--   -> DROP the two _obs_temp tables

-- ---------------------------------------------------------------------
-- Stage 1a: distinct in-study encounter refs (native-linkage probe set).
-- ---------------------------------------------------------------------
CREATE TABLE {{ prefix }}__cohort_study_population_temp_enc AS
SELECT DISTINCT
    encounter_ref
FROM {{ prefix }}__cohort_study_population
WHERE encounter_ref IS NOT NULL
;

-- ---------------------------------------------------------------------
-- Stage 1b: per-subject in-study date span (date-fallback bounds).
-- Uses the normalized, NULL-free window end (enc_period_end_day_filled).
-- ---------------------------------------------------------------------
CREATE TABLE {{ prefix }}__cohort_study_population_temp_subject AS
SELECT
    subject_ref,
    MIN(enc_period_start_day)       AS min_enc_day,
    MAX(enc_period_end_day_filled)  AS max_enc_day
FROM {{ prefix }}__cohort_study_population
WHERE encounter_ref IS NOT NULL
GROUP BY subject_ref
;

-- ---------------------------------------------------------------------
-- Stage 2: the ONLY scan of core__observation.
-- ---------------------------------------------------------------------
CREATE TABLE {{ prefix }}__cohort_study_population_obs AS
SELECT
    obs.category_code                     AS category_code,
    obs.category_system                   AS category_system,

    obs.status                            AS status,
    obs.observation_code                  AS observation_code,
    obs.observation_system                AS observation_system,

    obs.interpretation_code               AS interpretation_code,
    obs.interpretation_system             AS interpretation_system,
    obs.interpretation_display            AS interpretation_display,

    obs.effectivedatetime                 AS effectivedatetime,
    COALESCE(
        obs.effectivedatetime_day,
        DATE(obs.effectivedatetime)
    )                                     AS effectivedatetime_day,

    obs.valuecodeableconcept_code         AS valuecodeableconcept_code,
    obs.valuecodeableconcept_system       AS valuecodeableconcept_system,
    obs.valuecodeableconcept_display      AS valuecodeableconcept_display,

    obs.valuequantity_value               AS valuequantity_value,
    obs.valuequantity_comparator          AS valuequantity_comparator,
    obs.valuequantity_unit                AS valuequantity_unit,
    obs.valuequantity_system              AS valuequantity_system,
    obs.valuequantity_code                AS valuequantity_code,

    obs.valuestring                       AS valuestring,

    obs.dataabsentreason_code             AS dataabsentreason_code,
    obs.dataabsentreason_system           AS dataabsentreason_system,
    obs.dataabsentreason_display          AS dataabsentreason_display,

    obs.subject_ref                       AS subject_ref,
    obs.encounter_ref                     AS observation_encounter_ref,
    obs.specimen_ref                      AS specimen_ref,
    obs.observation_ref                   AS observation_ref,

    -- Native in-study linkage, decided per row (see note above).
    CASE WHEN enc.encounter_ref IS NOT NULL THEN 1 ELSE 0 END AS key_has_encounter

FROM core__observation AS obs

LEFT JOIN {{ prefix }}__cohort_study_population_temp_enc AS enc
    ON obs.encounter_ref = enc.encounter_ref

LEFT JOIN {{ prefix }}__cohort_study_population_temp_subject AS bounds
    ON obs.subject_ref = bounds.subject_ref

WHERE enc.encounter_ref IS NOT NULL
   OR (
        obs.encounter_ref IS NULL
        AND COALESCE(obs.effectivedatetime_day, DATE(obs.effectivedatetime))
            BETWEEN bounds.min_enc_day AND bounds.max_enc_day
      )
;

-- ---------------------------------------------------------------------
-- Stage 3: drop the helper tables. DROP removes the Glue metadata; the
-- underlying S3 data is NOT deleted by DROP -- clear the table's S3 prefix
-- (or use a bucket lifecycle rule) to reclaim storage. Within Cumulus the
-- prefix-managed teardown handles this on rebuild.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS {{ prefix }}__cohort_study_population_temp_enc;
DROP TABLE IF EXISTS {{ prefix }}__cohort_study_population_temp_subject;

-- ---------------------------------------------------------------------
-- INVARIANT CHECK (run once; expect 0). Confirms each observation_ref has
-- a single encounter_ref and is never split across null/non-null, which is
-- what makes the row-wise key_has_encounter equivalent to the window form.
--
--   SELECT COUNT(*) FROM (
--       SELECT observation_ref
--       FROM core__observation
--       WHERE observation_ref IS NOT NULL
--       GROUP BY observation_ref
--       HAVING COUNT(DISTINCT encounter_ref) > 1
--           OR (COUNT(encounter_ref) > 0
--               AND COUNT(encounter_ref) < COUNT(*))
--   );
--
-- If > 0, revert key_has_encounter to
--   MAX(CASE WHEN observation_encounter_ref IS NOT NULL THEN 1 ELSE 0 END)
--       OVER (PARTITION BY observation_ref)
-- in a Stage 2b CTAS over the (small) survivor table.
-- ---------------------------------------------------------------------































































