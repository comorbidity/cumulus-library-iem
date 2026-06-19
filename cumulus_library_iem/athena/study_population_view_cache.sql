-- optional: this can save time building study population to use an existing compiled stage.
CREATE OR REPLACE VIEW  iem__cohort_study_period                AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_period;
CREATE OR REPLACE VIEW  iem__cohort_study_population            AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population;
CREATE OR REPLACE VIEW  iem__cohort_study_population_enc	    AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population_enc;
CREATE OR REPLACE VIEW  iem__cohort_study_population_dx         AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population_dx;
CREATE OR REPLACE VIEW  iem__cohort_study_population_rx         AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population_rx;
CREATE OR REPLACE VIEW  iem__cohort_study_population_lab	    AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population_lab;
CREATE OR REPLACE VIEW  iem__cohort_study_population_proc       AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population_proc;
CREATE OR REPLACE VIEW  iem__cohort_study_population_doc	    AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population_doc;
CREATE OR REPLACE VIEW  iem__cohort_study_population_diag       AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population_diag;
CREATE OR REPLACE VIEW  iem__cohort_study_population_obs_base   AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population_obs_base;
CREATE OR REPLACE VIEW  iem__cohort_study_population_lab_base   AS SELECT * FROM cumulus_epic_study_dev_db.cache__iem_cohort_study_population_lab_base;
