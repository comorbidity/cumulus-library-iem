from pathlib import Path
from cumulus_library_iem.tools import (
    manifest,
    template,
    fhir_reference
)

#-----------------------------------------------------------------------------
# List of study population tables.
#
# cohort_study_period = patient encounters specified by "include_study_period"
#
# cohort_study_population = patient encounters with additional metadata
#
# cohort_study_population_{$Reference} = see `tools.fhir_reference.Reference`
#-----------------------------------------------------------------------------
STUDY_PERIOD = 'cohort_study_period'
STUDY_POPULATION = 'cohort_study_population'
OBS_TABLES = ['cohort_study_population_obs_base', 'cohort_study_population_lab_base']

###############################################################################
# Make
###############################################################################
def make_study_population(table_list:list) -> list[Path]:
    """
    :param table_list: list of tables to make with a template
    :return: list of files.sql
    """
    return [template.copy(f"{table}.sql") for table in table_list]

def make() -> list[Path]:
    """
    Study Population is built from "template/" dir.
    Study Population contains all Patient encounters matching criteria and all FHIR resources below.

    Study Builder then builds each `AspectKey`:
        dx = 'diagnoses'
        rx = 'medications'
        lab = 'labs'
        proc = 'procedures'
        doc = 'document'
        diag = 'diagnostic_report'

    Produces:
    * cohort_study_period.sql           -> Patient Encounters during study period
    * cohort_study_population.sql       -> Patient Encounters matching inclusion criteria
    * cohort_study_population_dx.sql    -> FHIR Condition
    * cohort_study_population_rx.sql    -> FHIR MedicationRequest
    * cohort_study_population_lab.sql   -> FHIR Observation.category=lab
    * cohort_study_population_doc.sql   -> FHIR DocumentReference
    * cohort_study_population_proc.sql  -> FHIR Procedure
    * cohort_study_population_diag.sql  -> FHIR DiagnosticReport

    :return: list of TOML outputs
    """
    file_upload = manifest.FileAction(
        file_list=['../spreadsheet/file_upload_population.toml'],
        description='inclusion/exclusion criteria for study population',
        build_type='build:parallel')

    study_period = make_study_population([STUDY_PERIOD])
    study_population = make_study_population([STUDY_POPULATION])
    obs_tables = make_study_population(OBS_TABLES)
    aspect_list = fhir_reference.list_aspect()
    aspect_tables = [f"{STUDY_POPULATION}_{aspect}" for aspect in aspect_list]
    aspect_tables = make_study_population(aspect_tables)

    actions = [
        file_upload,
        manifest.SqlAction(study_period, 'study_period'),
        manifest.SqlAction(study_population, 'study_population'),
        manifest.SqlAction(obs_tables, 'obs_base, lab_base', build_type='build:serial'),
        manifest.SqlAction(aspect_tables, f'study_population aspects {str(aspect_list)}'),
    ]

    return [manifest.save_actions_toml(actions, 'study_population.toml')]

if __name__ == '__main__':
    for manifest_toml in make():
        print(manifest_toml)
