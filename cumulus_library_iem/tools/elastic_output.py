from pathlib import Path
from cumulus_library_iem.tools.settings import ENCOUNTER_REF
from cumulus_library_iem.tools.fhir_reference import Aspect
from cumulus_library_iem.tools import manifest, tablespace, filetool, template

#-----------------------------------------------------------------------------
# ElasticSearch output
#-----------------------------------------------------------------------------
def path_output() -> Path:
    return filetool.path_project().parent / 'elastic_output'

def list_csv() -> list[Path]:
    output_path = path_output()
    if output_path and output_path.exists():
        return list(output_path.glob('*.csv'))
    return list()

#-----------------------------------------------------------------------------
# TOML files
#-----------------------------------------------------------------------------
def path_upload_toml() -> Path:
    return path_output() / 'file_upload_elastic.toml'

def path_stage_toml() -> Path:
     return filetool.path_project() / 'elastic_output.toml'

# def path_relative(path_list:list[Path])->list[str]:
#     return [f'athena/{file.name}' for file in path_list]

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------
def list_tables() -> list[str]:
    name_list = [filetool.file_to_simplename(file.name) for file in list_csv()]
    return [tablespace.name_join('elastic', name) for name in name_list]

def select_union(table_list: list[str]) -> str:
    sql = list()
    for table in table_list:
        table = tablespace.name_trim(table)
        select = f"\tSELECT '{table}'\t AS topic, * FROM {tablespace.name_join('elastic', table)}"
        sql.append(select)
    return ' UNION ALL\n'.join(sql)

#-----------------------------------------------------------------------------
# Make
#-----------------------------------------------------------------------------
def make_file_upload_toml() -> list[Path]:
    return [manifest.save_file_upload_toml(list_csv(), path_upload_toml())]

def make_union(aspect:Aspect=None) -> Path:
    cohort = f'union_{aspect.name}' if aspect else f'union'
    table_list = list_tables()
    return filetool.save_athena_view(
        tablespace.name_elastic(cohort),
        template.load(f"elastic_{cohort}.sql",
                      encounter_ref=ENCOUNTER_REF,
                      select_union=select_union(table_list))
    )

def make() -> list[Path]:
    if len(list_csv()) > 0:
        upload_file = 'file_upload_elastic.toml'
        union_list = [make_union(), make_union(Aspect.dx)]

        action_list = [manifest.FileAction(file_list=[f'../elastic_output/{upload_file}'],
                                           description='elastic_output CSV uploads',
                                           build_type='build:parallel'),
                       manifest.SqlAction(file_list=union_list,
                                          description='elastic_output UNION',
                                          build_type='build:serial')]

        todo_refactor = manifest.save_file_upload_toml(list_csv(), upload_file)
        return [manifest.save_actions_toml(action_list, 'elastic_output.toml')]
    return list()

if __name__ == '__main__':
    for output_toml in make():
        print(output_toml)
