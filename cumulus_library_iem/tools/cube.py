from pathlib import Path
from cumulus_library.builders.counts import CountsBuilder
from cumulus_library_iem.tools import filetool
from cumulus_library_iem.tools.tablespace import name_trim, name_cube, ctas_as_view
from cumulus_library_iem.tools.settings import CUBE_MIN_SUBJECTS, CUBE_AS_VIEW
from cumulus_library_iem.tools import manifest

MANIFEST = manifest.get_manifest()
PREFIX = MANIFEST.get_study_prefix()

def cube_fhir_resource(primary_id:str,
                       source_table='study_population',
                       table_cols=None,
                       table_name=None,
                       min_subject=CUBE_MIN_SUBJECTS) -> Path:
    """Generates a counts table using a template

    :param primary_id: The type of FHIR resource to count
    :param source_table: The table to create counts data from
    :param table_cols: The columns from the source table to add to the count table
    :param table_name: The name of the table to create. Must start with study prefix
    :param min_subject: Minimum number of patients to include in result groupings
    """
    if not table_name:
        count_type = primary_id.replace('_ref', '')
        count_type = count_type if (count_type!='subject') else 'patient'
        table_name = name_trim(source_table)
        table_name = name_cube(table_name, count_type)

    table_cols = sorted(list(set(table_cols)))
    sql = CountsBuilder(manifest=manifest.get_manifest()).get_count_query(
            table_name=table_name,
            source_table=source_table,
            table_cols=table_cols,
            min_subject=min_subject,
            primary_id=primary_id,
    )
    if CUBE_AS_VIEW == 1:
        sql = ctas_as_view(sql, table_name)

    return filetool.save_athena_view(table_name, sql)

def cube_patient(source_table='study_population',
                 table_cols=None,
                 table_name=None,
                 min_subject=CUBE_MIN_SUBJECTS) -> Path:
    return cube_fhir_resource(
        primary_id='subject_ref',
        source_table=source_table,
        table_cols=table_cols,
        table_name=table_name,
        min_subject=min_subject)

def cube_encounter(source_table='study_population',
                   table_cols=None,
                   table_name=None,
                   min_subject=CUBE_MIN_SUBJECTS) -> Path:
    return cube_fhir_resource(
        primary_id='encounter_ref',
        source_table=source_table,
        table_cols=table_cols,
        table_name=table_name,
        min_subject=min_subject)

def cube_document(source_table='study_population_doc',
                  table_cols=None,
                  table_name=None,
                  min_subject=CUBE_MIN_SUBJECTS) -> Path:
    return cube_fhir_resource(
        primary_id='documentreference_ref',
        source_table=source_table,
        table_cols=table_cols,
        table_name=table_name,
        min_subject=min_subject)

def cube_diagnostic(source_table='study_population_doc',
                    table_cols=None,
                    table_name=None,
                    min_subject=CUBE_MIN_SUBJECTS) -> Path:
    return cube_fhir_resource(
        primary_id='diagnosticreport_ref',
        source_table=source_table,
        table_cols=table_cols,
        table_name=table_name,
        min_subject=min_subject)

def cube_note(source_table='sample_casedef',
              table_cols=None,
              table_name=None,
              min_subject=CUBE_MIN_SUBJECTS) -> Path:
    return cube_fhir_resource(
        primary_id='note_ref',
        source_table=source_table,
        table_cols=table_cols,
        table_name=table_name,
        min_subject=min_subject)
