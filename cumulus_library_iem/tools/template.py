from pathlib import Path
from jinja2 import Environment, FileSystemLoader, StrictUndefined
from cumulus_library_iem.tools import filetool
from cumulus_library_iem.tools.manifest import PREFIX

#-----------------------------------------------------------------------------
# Load
#-----------------------------------------------------------------------------
def load(file_sql: str, **kwargs) -> str:
    """
    sql = load("meta_version.sql", data_package_version="1.0.0")
    sql = load("sample_casedef_temporality.sql", temporality="pre")
    """
    return _render(filetool.path_template(), file_sql, **kwargs)

def load_test(file_sql: str, **kwargs) -> str:
    """Render from tests/template/ -- keeps QA/test SQL out of the production template/ folder."""
    return _render(filetool.path_tests_template(), file_sql, **kwargs)

#-----------------------------------------------------------------------------
# Copy
#-----------------------------------------------------------------------------
def copy(file_sql: Path | str, **kwargs) -> Path:
    """Render template/ -> athena/{PREFIX}__<name>.sql"""
    return _copy(filetool.path_template(), filetool.path_athena, file_sql, **kwargs)

def copy_test(file_sql: Path | str, **kwargs) -> Path:
    """Render tests/template/ -> tests/athena/{PREFIX}__<name>.sql"""
    return _copy(filetool.path_tests_template(), filetool.path_tests_athena, file_sql, **kwargs)

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------
def _render(template_dir: Path, file_sql: str, **kwargs) -> str:
    """Render a Jinja SQL template found in `template_dir`."""
    kwargs.setdefault("prefix", PREFIX)
    env = Environment(loader=FileSystemLoader(str(template_dir)),
                      undefined=StrictUndefined)
    return env.get_template(file_sql).render(**kwargs)

def _copy(template_dir: Path, athena_path, file_sql: Path | str, **kwargs) -> Path:
    """Render `file_sql` from `template_dir` and write it under `athena_path` as
    `{PREFIX}__<file_name>`."""
    file_name = file_sql.name if isinstance(file_sql, Path) else file_sql
    text = _render(template_dir, file_name, **kwargs)
    return filetool.write_text(text, athena_path(f"{PREFIX}__{file_name}"))
