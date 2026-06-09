from pathlib import Path
from functools import lru_cache
from cumulus_library import StudyManifest
from cumulus_library_iem.tools import filetool

#-----------------------------------------------------------------------------
# get study manifest using cumulus library
#-----------------------------------------------------------------------------
@lru_cache(maxsize=1)
def get_manifest(manifest_path: Path|str = None) -> StudyManifest:
    """
    This method encapsulated changes to v6 StudyManifest
    default: filetool.path_project() = "cumulus_library_irae_cds"

    :param manifest_path: optional path to manifest file
    :return: StudyManifest
    """
    if not manifest_path:
        manifest_path = filetool.path_project()
    if isinstance(manifest_path, str):
        manifest_path = filetool.path_project(manifest_path)
    return StudyManifest(manifest_path)

#-----------------------------------------------------------------------------
# LOAD ONCE
#-----------------------------------------------------------------------------
MANIFEST = get_manifest()
PREFIX = get_manifest().get_study_prefix()

#-----------------------------------------------------------------------------
# TOML builders
# (Future migrate to Jinja template, DICT type or TOML_lib)
#-----------------------------------------------------------------------------
def as_sql_toml(file_list:list[Path], description:str=None, build_type='build:parallel') -> str:
    """
    @Refactor: TOML templates be Jinja `template.py`

    :param description: key name to display during build
    :param file_list: list of paths to files to execute in parallel
    :param build_type: typically "build:parallel" or "build:serial"
    :return: str content for `manifest.toml` submanifest
    """
    _files = [_quote('athena/'+f.name) for f in file_list]
    return _actions(description, build_type, 'files', _files)

def as_export_toml(file_list:list[Path], description:str=None, export_type='export:counts') -> str:
    """
    @Refactor: TOML templates be Jinja `template.py`

    :param description: key name to display during build
    :param file_list: list of paths to files to execute in parallel
    :param export_type: supports one of ['export:counts', 'export:annotated_counts', 'export:flat', 'export:metadata']
    :return: str content for `manifest.toml` submanifest
    """
    _tables = [_quote(f.stem) for f in file_list]
    return _actions(description, export_type, 'tables', _tables)

def as_file_upload_toml(file_list:list[Path]) -> str:
    """
    @Refactor: TOML templates be Jinja `template.py`
    :return: str content for `manifest.toml` submanifest
    """
    out = ['config_type="file_upload"\n']
    for filename in file_list:
        simple  = filetool.file_to_simplename(filename.name)
        if 'include' in filename.name:
            out.append(f'[tables.{simple}]')
        else:
            out.append(f'[tables.valueset_{simple}]')
        out.append(f'file = "{filename.name}"')
        out.append('')
    return '\n'.join(out)

def save_file_upload_toml(file_list:list[Path], toml_file:Path|str) -> Path:
    if not isinstance(toml_file, Path):
        toml_file = filetool.path_spreadsheet(toml_file)
    content=as_file_upload_toml(file_list)
    return save_text_toml(content=content, toml_file=toml_file)

def save_sql_toml(file_list: list[Path], toml_file: Path|str, description:str = None, build='build:parallel') -> Path:
    content = as_sql_toml(file_list, description, build)
    return save_text_toml(content=content, toml_file=toml_file)

def save_lines_toml(lines: list[str], toml_file: Path|str) -> Path:
    content = '\n'.join(lines)
    return save_text_toml(content=content, toml_file=toml_file)

def save_text_toml(content:str, toml_file:Path|str) -> Path:
    if not isinstance(toml_file, Path):
        toml_file = filetool.path_project(toml_file)
    return filetool.write_text(content.strip(), toml_file)

#-----------------------------------------------------------------------------
# TOML helpers
#-----------------------------------------------------------------------------
def _actions(description, action_type, key, values:list[str]) -> str:
    lines = [_description(description),
             _type(action_type),
             _dict(key, values)]
    return f"\n[[actions]]\n" + '\n'.join(lines)

def _description(description:str = None) -> str:
    return f'description={_quote(description)}'

def _type(toml_type:str=None) -> str:
    return f'type={_quote(toml_type)}'

def _dict(key, values_list:list=None) -> str:
    return f'{key}= [\n\t'+ ',\n\t'.join(values_list) + '\n]'

def _quote(text:str, quote_char:str='"') -> str:
    """
    :param text:
    :param quote_char: should be double quotes
    :return:
    """
    if not text:
        return f'{quote_char}{quote_char}'

    text = text.replace('[', '(')
    text = text.replace(']', ')')
    return f'{quote_char}{text}{quote_char}'
