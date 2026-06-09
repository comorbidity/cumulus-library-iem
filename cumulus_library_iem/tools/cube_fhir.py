from pathlib import Path
from cumulus_library_iem.tools import manifest, study_meta
from cumulus_library_iem.tools.cube import PREFIX
from cumulus_library_iem.tools.cube import (
    cube_patient,
    cube_encounter,
    cube_note,
    cube_document,
    cube_diagnostic
)

#-----------------------------------------------------------------------------
# Make CUBE for casedef
#-----------------------------------------------------------------------------
def make_study_population() -> list[Path]:
    return [
        # encounters for study population
        cube_encounter(source_table=f'{PREFIX}__cohort_study_population_enc',
                       table_cols=['age_group',
                                   'age_at_visit',
                                   'enc_period_start_year',
                                   'enc_class_display',
                                   'enc_type_display',
                                   'enc_servicetype_display']),

        # patients for study population
        cube_patient(source_table=f'{PREFIX}__cohort_study_population',
                     table_cols=['age_group',
                                 'gender',
                                 'race_display']),

        # Diagnosis
        cube_patient(source_table=f'{PREFIX}__cohort_study_population_dx',
                     table_cols=['age_group',
                                 'dx_category_code',
                                 'dx_system',
                                 'dx_code',
                                 'dx_display']),

        # Medications
        cube_patient(source_table=f'{PREFIX}__cohort_study_population_rx',
                     table_cols=['age_group',
                                 'rx_category_code',
                                 'rx_system',
                                 'rx_code',
                                 'rx_display']),

        # Procedures
        cube_patient(source_table=f'{PREFIX}__cohort_study_population_proc',
                     table_cols=['age_group',
                                 'proc_category_display',
                                 'proc_system',
                                 'proc_code',
                                 'proc_display']),

        # Lab Observations
        cube_patient(source_table=f'{PREFIX}__cohort_study_population_lab',
                     table_cols=['age_group',
                                 'lab_observation_system',
                                 'lab_observation_code',
                                 'lab_observation_display']),

        # Documents
        cube_patient(source_table=f'{PREFIX}__cohort_study_population_doc',
                     table_cols=['age_group',
                                 'doc_type_display',
                                 'aux_has_text']),

        cube_encounter(source_table=f'{PREFIX}__cohort_study_population_doc',
                       table_cols=['enc_class_display',
                                   'enc_type_display',
                                   'enc_servicetype_display']),

        cube_document(source_table=f'{PREFIX}__cohort_study_population_doc',
                      table_cols=['doc_type_display',
                                  'enc_class_display',
                                  'enc_type_display',
                                  'enc_servicetype_display',
                                  'aux_has_text']),

        # Diagnostic Reports
        cube_patient(source_table=f'{PREFIX}__cohort_study_population_diag',
                     table_cols=['age_group',
                                 'diag_category_display_best',
                                 'diag_system',
                                 'diag_code',
                                 'diag_display',
                                 'aux_has_text']),

        cube_encounter(source_table=f'{PREFIX}__cohort_study_population_diag',
                        table_cols=['diag_category_display_best',
                                    'enc_class_display',
                                    'enc_type_display',
                                    'enc_servicetype_display']),

        cube_diagnostic(source_table=f'{PREFIX}__cohort_study_population_diag',
                        table_cols=['diag_category_display_best',
                                    'diag_display',
                                    'aux_has_text']),
    ]

#-----------------------------------------------------------------------------
# Make CUBE for casedef
#-----------------------------------------------------------------------------
def make_casedef() -> list[Path]:
    return [
        # Count encounters for casedef
        cube_encounter(source_table=f'{PREFIX}__cohort_casedef',
                       table_cols=['age_at_casedef_min',
                                   'age_at_visit',
                                   'enc_class_display',
                                   'enc_type_display',
                                   'enc_servicetype_display']),

        # Count patients for casedef
        cube_patient(source_table=f'{PREFIX}__cohort_casedef',
                     table_cols=['age_at_casedef_min',
                                 'age_group',
                                 'gender',
                                 'system',
                                 'code',
                                 'display']),

        # DX Diagnoses
        cube_patient(source_table=f'{PREFIX}__cohort_casedef_dx',
                     table_cols=['variable',
                                 'dx_category_code',
                                 'dx_code',
                                 'dx_display']),

        # RX Medications
        cube_patient(source_table=f'{PREFIX}__cohort_casedef_rx',
                     table_cols=['variable',
                                 'rx_category_code',
                                 'rx_status',
                                 'rx_code',
                                 'rx_display']),

        # Lab Observations
        cube_patient(source_table=f'{PREFIX}__cohort_casedef_lab',
                     table_cols=['variable',
                                 'lab_observation_system',
                                 'lab_observation_code',
                                 'lab_observation_display']),

        # Procedures
        cube_patient(source_table=f'{PREFIX}__cohort_casedef_proc',
                     table_cols=['proc_category_display',
                                 'proc_system',
                                 'proc_code',
                                 'proc_display']),
    ]

#-----------------------------------------------------------------------------
# Make CUBE for casedef SAMPLES
#-----------------------------------------------------------------------------
def make_casedef_samples() -> list[Path]:
    table_cols = ['fhir_resource',
                  'note_code',
                  'note_display',
                  'note_system']

    sample_casedef = f'{PREFIX}__sample_casedef'
    temporality = ['pre', 'peri', 'peri_post', 'post']

    source_table_list = [sample_casedef]
    source_table_list+= [f'{sample_casedef}_{t}' for t in temporality]

    target_output = [cube_patient(source_table, table_cols) for source_table in source_table_list]
    target_output+= [cube_note(source_table, table_cols) for source_table in source_table_list]

    return target_output

#-----------------------------------------------------------------------------
# Make FHIR variables
#-----------------------------------------------------------------------------
def make_variable_union() -> list[Path]:
    return [
        cube_patient(source_table=f'{PREFIX}__cohort_variable_union',
                     table_cols=['age_group',
                                 'variable',
                                 'code',
                                 'system',
                                 'display']),

        cube_encounter(source_table=f'{PREFIX}__cohort_variable_union',
                       table_cols=['variable',
                                   'display',
                                   'enc_type_display',
                                   'enc_servicetype_display',
                                   'age_group'])
    ]


def make() -> list[Path]:
    study_population_sql_list = make_study_population()
    casedef_sql_list = make_casedef()
    sample_sql_list = make_casedef_samples()
    variable_sql_list = make_variable_union()

    sql_list = [
        manifest.as_sql_toml(study_population_sql_list, 'SQL cube study population'),
        manifest.as_sql_toml(variable_sql_list, 'SQL cube variable union'),
        manifest.as_sql_toml(casedef_sql_list, 'SQL cube casedef'),
        manifest.as_sql_toml(sample_sql_list, 'SQL cube casedef sample')
    ]

    export_list = [
        manifest.as_export_toml(study_population_sql_list, 'export cube tables study populations'),
        manifest.as_export_toml(variable_sql_list, 'export cube tables variable union'),
        manifest.as_export_toml(casedef_sql_list, 'export cube tables casedef'),
        manifest.as_export_toml(sample_sql_list, 'export cube tables casedef sample')
    ]

    sections = sql_list + export_list + study_meta.make_inline()

    return [manifest.save_lines_toml(sections, 'cube.toml')]

#-----------------------------------------------------------------------------
# MAIN method
#-----------------------------------------------------------------------------
if __name__ == "__main__":
    for output_toml in make():
        print(output_toml)
