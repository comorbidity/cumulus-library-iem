from pathlib import Path
from cumulus_library_iem.tools.fhir_reference import Aspect
from cumulus_library_iem.tools import settings, manifest, tablespace, filetool, template

#-----------------------------------------------------------------------------
# ElasticSearch output
#-----------------------------------------------------------------------------
def list_csv() -> list[Path]:
    output_path = filetool.path_elastic_output()
    if output_path and output_path.exists():
        return list(output_path.glob('*.csv'))
    return list()

#-----------------------------------------------------------------------------
# TOML files
#-----------------------------------------------------------------------------
def path_upload_toml() -> Path:
    return filetool.path_elastic_output() / 'file_upload_elastic.toml'

def path_stage_toml() -> Path:
     return filetool.path_project() / 'elastic_output.toml'

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------
def list_tables() -> list[str]:
    name_list = [filetool.file_to_simplename(file.name) for file in list_csv()]
    return [tablespace.name_elastic(name) for name in name_list]

def select_union(table_list: list[str]) -> str:
    sql = list()
    for table in table_list:
        table = tablespace.name_trim(table)
        select = f"\tSELECT '{table}'\t AS topic, * FROM {tablespace.name_elastic(table)}"
        sql.append(select)
    return ' UNION ALL\n'.join(sql)

#-----------------------------------------------------------------------------
# Make
#-----------------------------------------------------------------------------
def make_file_upload_toml() -> list[Path]:
    return [manifest.save_file_upload_toml(list_csv(), path_upload_toml(), table_prefix='elastic')]

def make_union() -> list[Path]:
    file_list = [_make_union(), _make_union(Aspect.dx)]
    return [manifest.save_sql_toml(file_list, path_stage_toml(), 'Elastic Union', 'build:serial')]

def _make_union(aspect:Aspect=None) -> Path:
    cohort = f'union_{aspect.name}' if aspect else f'union'
    table_list = list_tables()
    return filetool.save_athena_view(
        tablespace.name_elastic(cohort),
        template.load(f"elastic_{cohort}.sql", select_union=select_union(table_list))
    )

def make() -> list[Path]:
    if len(list_csv()) > 0:
        return make_file_upload_toml() + make_union()
    return list()

if __name__ == '__main__':
    for output_toml in make():
        print(output_toml)
