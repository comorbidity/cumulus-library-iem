from pathlib import Path
from jinja2 import Environment, FileSystemLoader, StrictUndefined
from cumulus_library_iem.tools import filetool
from cumulus_library_iem.tools.manifest import PREFIX

def load(file_sql: str, **kwargs) -> str:
    """
        sql = load("meta_version.sql", data_package_version="1.0.0")
        sql = load("sample_casedef_temporality.sql", temporality="pre")
    """
    kwargs.setdefault("prefix", PREFIX)
    env = Environment(loader=FileSystemLoader(str(filetool.path_template())),
                      undefined=StrictUndefined)
    template = env.get_template(file_sql)
    return template.render(**kwargs)

def copy(file_sql: Path | str, **kwargs) -> Path:
    file_name = file_sql.name if isinstance(file_sql, Path) else file_sql
    text = load(file_sql, **kwargs)
    target = filetool.path_athena(f"{PREFIX}__{file_name}")
    return filetool.save_athena(target, text)