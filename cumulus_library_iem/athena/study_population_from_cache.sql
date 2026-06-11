-- optional: this can save time building study population to use an existing compiled stage.
CREATE OR REPLACE VIEW iem__cohort_study_period	        as select * from all__cohort_study_period;
CREATE OR REPLACE VIEW iem__cohort_study_population	    as select * from all__cohort_study_population;
CREATE OR REPLACE VIEW iem__cohort_study_population_enc	as select * from all__cohort_study_population_enc;
CREATE OR REPLACE VIEW iem__cohort_study_population_dx  as select * from all__cohort_study_population_dx;
CREATE OR REPLACE VIEW iem__cohort_study_population_rx  as select * from all__cohort_study_population_rx;
CREATE OR REPLACE VIEW iem__cohort_study_population_lab	as select * from all__cohort_study_population_lab;
CREATE OR REPLACE VIEW iem__cohort_study_population_proc as select * from all__cohort_study_population_proc;
CREATE OR REPLACE VIEW iem__cohort_study_population_doc	as select * from all__cohort_study_population_doc;
CREATE OR REPLACE VIEW iem__cohort_study_population_diag as select * from all__cohort_study_population_diag;
