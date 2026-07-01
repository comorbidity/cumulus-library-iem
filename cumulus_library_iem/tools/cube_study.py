from pathlib import Path
from cumulus_library_iem.tools import manifest, study_meta, tablespace
from cumulus_library_iem.tools.cube import PREFIX
from cumulus_library_iem.tools.cube import (
    cube_patient,
    cube_encounter,
    cube_note,
    cube_document,
    cube_diagnostic
)


#-----------------------------------------------------------------------------
# Make FHIR variables
#-----------------------------------------------------------------------------
def make_variable_union() -> list[Path]:
    return [
        cube_patient(source_table=f'{PREFIX}__cohort_variable_union',
                     table_name=tablespace.name_cube('fhir', 'patient'),
                     table_cols=['age_group',
                                 'variable',
                                 'code',
                                 'system',
                                 'display']),

        # cube_encounter(source_table=f'{PREFIX}__cohort_variable_union',
        #                table_cols=['variable',
        #                            'display',
        #                            'enc_type_display',
        #                            'enc_servicetype_display',
        #                            'age_group'])
    ]

#-----------------------------------------------------------------------------
# Make Elastic results
#-----------------------------------------------------------------------------
def make_elastic_union() -> list[Path]:
    return [
        cube_patient(source_table=f'{PREFIX}__elastic_union',
                     table_name=tablespace.name_cube('elastic', 'patient'),
                     table_cols=['topic','document_title']),

        # cube_encounter(source_table=f'{PREFIX}__elastic_union',
        #                table_name=tablespace.name_cube('elastic', 'encounter'),
        #                table_cols=['topic', 'document_title']),

        cube_note(source_table=f'{PREFIX}__elastic_union',
                  table_name=tablespace.name_cube('elastic', 'note'),
                  table_cols=['topic', 'document_title'])
    ]

def make_elastic_union_dx() -> list[Path]:
    return [
        cube_patient(source_table=f'{PREFIX}__elastic_union_dx',
                     table_name=tablespace.name_cube('union_fhir_elastic', 'patient'),
                     table_cols=['variable',
                                 'match_fhir',
                                 'match_elastic',
                                 'match_both',
                                 'enc_period_start_year',
                                 # 'age_group',
                                 'gender'
                                 ]),


        cube_note(source_table=f'{PREFIX}__elastic_union_dx',
                  table_name=tablespace.name_cube('union_fhir_elastic', 'note'),
                  table_cols=['variable',
                              'match_fhir',
                              'match_elastic',
                              'match_both',
                              'document_title',
                              'enc_class_code']),
    ]

#-----------------------------------------------------------------------------
# Make
#-----------------------------------------------------------------------------
def make() -> list[Path]:
    variable_union = make_variable_union()
    elastic_union = make_elastic_union()
    elastic_union_dx = make_elastic_union_dx()

    sql_list = [
        manifest.SqlAction(variable_union, 'SQL cube variable union'),
        manifest.SqlAction(elastic_union, 'SQL cube elastic union'),
        manifest.SqlAction(elastic_union_dx, 'SQL cube elastic union dx (with FHIR)'),
    ]

    export_list = [
        manifest.ExportAction(variable_union, 'export cube tables variable union'),
        manifest.ExportAction(elastic_union, 'export cube elastic union'),
        manifest.ExportAction(elastic_union_dx, 'export cube elastic union dx (with FHIR)'),
    ]

    actions = sql_list + export_list + study_meta.make_actions()

    return [manifest.save_actions_toml(actions, 'cube.toml')]

#-----------------------------------------------------------------------------
# MAIN method
#-----------------------------------------------------------------------------
if __name__ == "__main__":
    for output_toml in make():
        print(output_toml)
