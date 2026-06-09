from pathlib import Path
from cumulus_library_iem.tools import filetool, tablespace, manifest, template, fhir_reference
from cumulus_library_iem.tools.fhir_reference import Aspect
from cumulus_library_iem.tools.tablespace import name_trim, name_cohort
from cumulus_library_iem.tools.study_variable import (
    list_variables,
    list_variables_as_str,
    list_aspects
)

#-----------------------------------------------------------------------------
# Step 1) UNION ALL
#-----------------------------------------------------------------------------
def make_variable_union_bool() -> list[Path]:
    """
    1.1 Create table of all variable cohorts together (UNION ALL) having a single column
        `variable` which denotes the cohort source.

    :return: path to cohort_variable_union.sql
    """
    return [_make_variable_union(aspect=None)]

def make_variable_union_aspect() -> list[Path]:
    """
    1.2 Create tables of variables grouped by Aspect

    :return: [cohort_variable_union_lab.sql,
             cohort_variable_union_diag.sql,
             cohort_variable_union_doc.sql,
             cohort_variable_union_rx.sql]
    """
    return [_make_variable_union(aspect=aspect) for aspect in list_aspects()]

def _make_variable_union(aspect:Aspect=None) -> Path:
    """
    :param aspect: variable types to union, or None= all variables
    :return: Path to SQL file
    """
    cohort = f'variable_union_{aspect.name}' if aspect else f'variable_union'
    variable_list = list_variables(aspect)
    return filetool.save_athena_view(
        name_cohort(cohort),
        template.load(f"cohort_{cohort}.sql",
                      select_union=select_union(variable_list),
                      variable_list=list_variables_as_str(variable_list)))

def select_union(variable_list: list[str]) -> str:
    """
    @refactor to Jinja template
    Get SQL select UNION ALL statement from a list of variable names.

    :param variable_list: variable names (typically list of valuesets)
    :return: str SQL select UNION ALL for the provided variable list
    """
    sql = list()
    for variable in variable_list:
        variable = name_trim(variable)
        select = f"\tSELECT '{variable}'\t AS variable, code, display, system, encounter_ref"
        select+= f", {fhir_reference.get_column(variable).reference} AS resource_ref"
        from_table = f" FROM {tablespace.PREFIX}__cohort_{variable}"
        sql.append(select + from_table)
    return ' UNION ALL\n'.join(sql)

#-----------------------------------------------------------------------------
# Step 2) WIDE table with all variables
#-----------------------------------------------------------------------------
def make_variable_wide_bool(aspect:Aspect=None) -> Path:
    """
    All study variable cohorts in one table in WIDE format.
    each variable has a single column denoting
        True == present variable per encounter
        False == absent variable per encounter

    :return: Path to SQL file
    """
    cohort = f'variable_wide_{aspect.name}' if aspect else f'variable_wide'
    variable_list = list_variables(aspect)
    return filetool.save_athena_view(
        name_cohort(cohort),
        template.load(f"cohort_{cohort}.sql",
                      select_wide_bool=select_wide_bool(variable_list),
                      select_wide_any=select_wide_any(variable_list)))

def select_wide_bool(variable_list: list[str]) -> str:
    """
    "Wide" turns each variable value into a named column,
    "bool" denotes variable present(True) or absent(False).

    @refactor to Jinja template
    :param variable_list: variable names (typically list of valuesets)
    :return: str SQL select variable table as column name
    """
    sql = list()
    for variable in variable_list:
        variable = name_trim(variable)
        sql.append(f"\t\tIF(variable='{variable}', True) AS {variable}")
    return '\t'+ ',\n'.join(sql).strip()

def select_wide_any(variable_list: list[str]) -> str:
    """
    "Wide" variable is expected to already be a binary column.
    "any" denotes variable is present(True) at least once (1+).

    Select "arbitrary" is an optimization that compresses rows such that if a single
    variable instance is found for an encounter_ref, the search condition is reached (1+),
    table search ends, allowing for the next variable search.

    https://prestodb.io/docs/current/functions/aggregate.html#arbitrary-x-same-as-input

    @refactor to Jinja template
    :param variable_list: variable names (typically list of valuesets)
    :return: str SQL select variable for any arbitrary match
    """
    sql = list()
    for variable in variable_list:
        variable = name_trim(variable)
        sql.append(f"\t\tarbitrary({variable}) FILTER (where {variable} ) as {variable}")
    return '\t' + ',\n'.join(sql).strip()

#-----------------------------------------------------------------------------
# (3) WIDE table for each aspect
#-----------------------------------------------------------------------------
def make_variable_wide() -> list[Path]:
    """
    :return: list of SQL files for each aspect
            * cohort_variable_wide_lab
            * cohort_variable_wide_diag
            * cohort_variable_wide_dx
            * cohort_variable_wide_rx
    """
    return [_make_variable_wide(aspect) for aspect in list_aspects()]

def _make_variable_wide(aspect:Aspect, generator=None) -> Path:
    """
    :param aspect: aspect to make variable wide for
    :param generator: select_wide_*** function
    :return: Path to SQL file
    """
    if not generator:
        if aspect == Aspect.dx:
            return _make_variable_wide(aspect, select_wide_dx)
        elif aspect == Aspect.lab:
            return _make_variable_wide(aspect, select_wide_lab)
        elif aspect == Aspect.diag:
            return _make_variable_wide(aspect, select_wide_diag)
        elif aspect == Aspect.doc:
            return _make_variable_wide(aspect, select_wide_doc)
        elif aspect == Aspect.rx:
            return _make_variable_wide(aspect, select_wide_rx)
        elif aspect == Aspect.proc:
            return _make_variable_wide(aspect, select_wide_proc)
        else:
            raise NotImplementedError(f"'{aspect}' aspect type not yet supported.")
    else:
        cohort = f'variable_wide_{aspect.name}'
        return filetool.save_athena_view(
            name_cohort(cohort),
            template.load(f"cohort_variable_wide_aspect.sql",
                          aspect=aspect.name,
                          select_wide_dict=generator()))

def select_wide_dict(variable_list:list[str], columns:dict) -> str:
    """
    Generic helper method for turning a single variable column into multiple columns.

    "Wide" denotes turning a variable value into column(s),
    "dict" denotes Key=Val pairs of the original column name to wide column name.

    :param variable_list: any variable name like `diag_mre_enterography`
    :param columns: study population column names with simple suffix value
    :return: string SQL
    """
    sql = list()
    for variable in variable_list:
        for key, val in columns.items():
            sql.append(f"IF(variable='{variable}', {key}) AS {variable}_{val}")
    return ',\n'.join(sql).strip()

def select_wide_dx(variable_list: list[str] = None, columns: dict = None) -> str:
    """
    FHIR Condition attributes
    * https://build.fhir.org/condition-definitions.html#Condition.clinicalStatus
    * https://build.fhir.org/condition-definitions.html#Condition.onset_x_
    * https://build.fhir.org/condition-definitions.html#Condition.category

    :param variable_list: default= Dx variables
    :param columns: default Dx
    :return: str SQL
    """
    if not variable_list:
        variable_list = list_variables(Aspect.dx)
    if not columns:
        columns = {'dx_onset_date': 'onset',
                   'dx_category_code':'category',
                   'dx_clinical_status': 'status',
                   'condition_ref': 'ref'}
    return select_wide_dict(variable_list, columns)

def select_wide_rx(variable_list: list[str] = None, columns: dict = None) -> str:
    """
    FHIR MedicationRequest attributes
    * https://build.fhir.org/medicationrequest-definitions.html#MedicationRequest.status
    * https://build.fhir.org/medicationrequest-definitions.html#MedicationRequest.category
    * https://build.fhir.org/medicationrequest-definitions.html#MedicationRequest.authoredOn

    :param variable_list: default=medication variables
    :param columns: default Rx status, category, authoredOn, and FHIR reference
    :return: str SQL
    """
    if not variable_list:
        variable_list = list_variables(Aspect.rx)
    if not columns:
        columns = {'rx_authoredon_date': 'date',
                   'rx_status': 'status',
                   'rx_category_code': 'category',
                   'medicationrequest_ref': 'ref'}
    return select_wide_dict(variable_list, columns)

def select_wide_lab(variable_list: list[str]=None, columns:dict = None) -> str:
    """
    FHIR Observation('laboratory') attributes
    * https://build.fhir.org/observation-definitions.html#Observation.effective_x_
    * https://build.fhir.org/observation-definitions.html#Observation.interpretation
    * https://build.fhir.org/observation-definitions.html#Observation.value_x_

    :param variable_list: default= Laboratory variables
    :param columns: default= effective date, interpretation, value, unit, FHIR reference
    :return: str SQL
    """
    if not variable_list:
        variable_list = list_variables(Aspect.lab)
    if not columns:
        columns = {'lab_effectivedate': 'date',
                   'lab_interpretation_code': 'interpretation',
                   'lab_valuequantity_value': 'value',
                   'lab_valuequantity_unit': 'unit',
                   'observation_ref': 'ref'}
    return select_wide_dict(variable_list, columns)

def select_wide_diag(variable_list: list[str] = None, columns: dict = None) -> str:
    """
    FHIR DiagnosticReport attributes
    * https://build.fhir.org/diagnosticreport-definitions.html#DiagnosticReport.category
    * https://build.fhir.org/diagnosticreport-definitions.html#DiagnosticReport.code
    * https://build.fhir.org/diagnosticreport-definitions.html#DiagnosticReport.effective_x_

    :param variable_list: default= Diagnostic report variables
    :param columns: default = effective date, code, FHIR reference
    :return: str SQL
    """
    if not variable_list:
        variable_list = list_variables(Aspect.diag)
    if not columns:
        columns = {'diag_effectivedatetime_day': 'date',
                   'diag_code': 'code',
                   'diagnosticreport_ref': 'ref'}
    return select_wide_dict(variable_list, columns)

def select_wide_doc(variable_list: list[str] = None, columns: dict = None) -> str:
    """
    FHIR DocumentReference
    * https://build.fhir.org/documentreference.html
z
    :param variable_list: default = Document Reference variables
    :param columns: default= author date, code
    :return: str SQL
    """
    if not variable_list:
        variable_list = list_variables(Aspect.doc)
    if not columns:
        columns = {'doc_author_day': 'date',
                   'doc_type_code': 'code',
                   'documentreference_ref': 'ref'}
    return select_wide_dict(variable_list, columns)

def select_wide_proc(variable_list: list[str] = None, columns: dict = None) -> str:
    """
    FHIR Procedure
    * https://build.fhir.org/procedure.html
    * https://build.fhir.org/procedure-definitions.html#Procedure.performer.period
    * https://build.fhir.org/procedure-definitions.html#Procedure.category

    :param variable_list: default = Procedure variables
    :param columns: default= author date, code
    :return: str SQL
    """
    if not variable_list:
        variable_list = list_variables(Aspect.proc)
    if not columns:
        columns = {'proc_performed_day': 'date',
                   'proc_category_code': 'code',
                   'procedure_ref': 'ref'}
    return select_wide_dict(variable_list, columns)

#-----------------------------------------------------------------------------
# Make
#-----------------------------------------------------------------------------
def make() -> list[Path]:
    """
    Make cohort UNION variables as one big table
    Make cohort WIDE variables as one big table (tabular with each column is a variable)
    :return: list of TOML outputs
    """
    aspect_list = [aspect.name for aspect in list_aspects()]

    sections = [manifest.as_sql_toml(make_variable_union_bool(), 'variable union (bool)'),
                manifest.as_sql_toml(make_variable_union_aspect(), f'variable union {aspect_list}'),
                manifest.as_sql_toml([make_variable_wide_bool()], 'variable wide (bool)'),
                manifest.as_sql_toml(make_variable_wide(), f'variable wide {aspect_list}'), ]

    return [manifest.save_lines_toml(sections, 'study_variable_wide.toml')]

if __name__ == '__main__':
    for output_toml in make():
        print(output_toml)
