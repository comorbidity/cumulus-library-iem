from pathlib import Path
from cumulus_library_iem.tools import manifest, template

DATA_PACKAGE_VERSION = 14

def make_study_meta_sql(data_package_version:int = DATA_PACKAGE_VERSION) -> list[Path]:
    """
    https://docs.smarthealthit.org/cumulus/library/creating-studies.html#metadata-tables
    """
    return [template.copy(f"meta_date.sql"),
            template.copy(f"meta_version.sql", data_package_version=str(data_package_version))]

def make_actions() -> list[manifest.SqlAction | manifest.ExportAction]:
    """
    Make SQL study metadata and export metadata actions.
    """
    file_list = make_study_meta_sql()

    return [
        manifest.SqlAction(file_list, 'SQL study metadata'),
        manifest.ExportAction(file_list, 'export study metadata', 'export:meta'),
    ]

def make() -> list[Path]:
    return [manifest.save_actions_toml(make_actions(), 'study_meta.toml')]

if __name__ == '__main__':
    for target in make():
        print(target)
