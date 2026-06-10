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

#-----------------------------------------------------------------------------
# Make Elastic results
#-----------------------------------------------------------------------------
def make_elastic_union() -> list[Path]:
    return [
        cube_patient(source_table=f'{PREFIX}__elastic_union',
                     table_cols=['elastic','document_title']),

        cube_encounter(source_table=f'{PREFIX}__elastic_union',
                     table_cols=['elastic', 'document_title'])
    ]

#-----------------------------------------------------------------------------
# Make
#-----------------------------------------------------------------------------
def make() -> list[Path]:
    variable_union = make_variable_union()
    elastic_union = make_elastic_union()

    sql_list = [
        manifest.as_sql_toml(variable_union, 'SQL cube variable union'),
        manifest.as_sql_toml(elastic_union, 'SQL cube elastic union'),
    ]

    export_list = [
        manifest.as_export_toml(variable_union, 'export cube tables variable union'),
        manifest.as_export_toml(elastic_union, 'export cube tables study populations'),
    ]

    sections = sql_list + export_list + study_meta.make_inline()

    return [manifest.save_lines_toml(sections, 'cube.toml')]

#-----------------------------------------------------------------------------
# MAIN method
#-----------------------------------------------------------------------------
if __name__ == "__main__":
    for output_toml in make():
        print(output_toml)
