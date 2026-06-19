-- optional: this can save time building study population to use an existing compiled stage.
CREATE TABLE  cache__iem_cohort_study_period	        AS SELECT * FROM iem__cohort_study_period;
CREATE TABLE  cache__iem_cohort_study_population	    AS SELECT * FROM iem__cohort_study_population;
CREATE TABLE  cache__iem_cohort_study_population_enc	AS SELECT * FROM iem__cohort_study_population_enc;
CREATE TABLE  cache__iem_cohort_study_population_dx     AS SELECT * FROM iem__cohort_study_population_dx;
CREATE TABLE  cache__iem_cohort_study_population_rx     AS SELECT * FROM iem__cohort_study_population_rx;
CREATE TABLE  cache__iem_cohort_study_population_lab	AS SELECT * FROM iem__cohort_study_population_lab;
CREATE TABLE  cache__iem_cohort_study_population_proc   AS SELECT * FROM iem__cohort_study_population_proc;
CREATE TABLE  cache__iem_cohort_study_population_doc	AS SELECT * FROM iem__cohort_study_population_doc;
CREATE TABLE  cache__iem_cohort_study_population_diag   AS SELECT * FROM iem__cohort_study_population_diag;
CREATE TABLE  cache__iem_cohort_study_population_obs_base	AS SELECT * FROM iem__cohort_study_population_obs_base;
CREATE TABLE  cache__iem_cohort_study_population_lab_base	AS SELECT * FROM iem__cohort_study_population_lab_base;
