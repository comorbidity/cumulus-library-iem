CREATE TABLE {{ prefix }}__cohort_study_population_lab_base AS
SELECT *
FROM {{ prefix }}__cohort_study_population_obs_base
WHERE category_code = 'laboratory'
;