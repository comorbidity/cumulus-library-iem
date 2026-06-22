from pathlib import Path
from cumulus_library_iem.tools import manifest, template

DATA_PACKAGE_VERSION = 14

def make_study_meta_sql(data_package_version:int = DATA_PACKAGE_VERSION) -> list[Path]:
    """
    https://docs.smarthealthit.org/cumulus/library/creating-studies.html#metadata-tables
    """
    return [template.copy(f"meta_date.sql"),
            template.copy(f"meta_version.sql", data_package_version=str(data_package_version))]

def make_inline()->list[str]:
    """
    Make SQL study meta and suggest TOML, example

    [[actions]]
    description = "export metadata"
    type = "build:serial"
    files = [
        'athena/iem__meta_date.sql',
        'athena/iem__meta_version.sql'
    ]

    [[actions]]
    description = "export metadata"
    type = "export:meta"
    tables = [
        'iem__meta_date',
        'iem__meta_version'
    ]
    """
    file_list = make_study_meta_sql()

    return [
        manifest.as_sql_toml(file_list, 'SQL study metadata'),
        manifest.as_export_toml(file_list, 'export study metadata', 'export:meta')
    ]

def make() -> list[Path]:
    return [manifest.save_lines_toml(make_inline(), 'study_meta.toml')]

if __name__ == '__main__':
    for target in make():
        print(target)
