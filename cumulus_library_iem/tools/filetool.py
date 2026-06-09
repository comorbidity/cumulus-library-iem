import os
import json
from pathlib import Path
from typing import Dict, Any
from cumulus_library_iem.tools import fhir_reference

#-----------------------------------------------------------------------------
# PROJECT HOME
#-----------------------------------------------------------------------------
def path_project(filename=None) -> Path:
    """
    :param filename: optional
    :return: path to home "project" directory `cumulus_library_iem`
    """
    project_dir = Path(__file__).resolve().parent.parent
    if filename:
        return project_dir/ filename
    return project_dir

#-----------------------------------------------------------------------------
# spreadsheet
#-----------------------------------------------------------------------------
def path_spreadsheet(filename: Path | str = None) -> Path:
    """
    :param filename: optional filename of spreadsheet
    :return: Path to spreadsheet file
    """
    if not filename:
        return path_project().parent / 'spreadsheet'
    return path_project().parent / 'spreadsheet' / filename

def list_spreadsheet(pattern:str = '*.*') -> list[Path]:
    """
    :param pattern: pattern, default *.*
    :return: list of spreadsheet files matching pattern
    """
    return filter_spreadsheet(sorted(list(path_spreadsheet('.').glob(pattern))))

def filter_spreadsheet(file_list:list[Path]) -> list[Path]:
    """
    :return: files with a known spreadsheet extension
    """
    accept = ['.csv', '.tsv', '.bsv']
    return [f for f in file_list if f.suffix.lower() in accept]

def filter_aspect(file_list:list[Path]) -> list[Path]:
    """
    @refactor
    """
    filtered = list()
    accept = fhir_reference.list_aspect()
    for f in file_list:
        if '_' in f.name:
            key = f.name.split('_')[0]
            if key in accept:
                filtered.append(f)
    return filtered

#-----------------------------------------------------------------------------
# SQL File(s)
#-----------------------------------------------------------------------------
def path_athena(file_sql: Path | str = None) -> Path:
    if not file_sql:
        return path_project() / 'athena'
    return path_project() / 'athena' / file_sql

def save_athena(file_sql: Path | str, contents: str) -> Path:
    return Path(write_text(contents, path_athena(file_sql)))

def save_athena_view(view_name: str, contents: str) -> Path:
    return Path(write_text(contents, path_athena(f'{view_name}.sql')))

def path_template(file_sql: Path | str = None) -> Path:
    if not file_sql:
        return path_project() / 'template'
    return path_project() / 'template' / file_sql

#-----------------------------------------------------------------------------
# LLM File(s)
#-----------------------------------------------------------------------------
def path_llm(filename: Path | str = None) -> Path:
    if not filename:
        return path_project() / 'llm'
    return path_project() / 'llm' / filename

def path_llm_builder(filename: Path | str = None) -> Path:
    if not filename:
        return path_llm() / 'builder'
    return path_llm() / 'builder' / filename

def path_llm_template(filename: Path | str = None) -> Path:
    if not filename:
        return path_llm() / 'template'
    return path_llm() / 'template' / filename

def path_llm_athena(filename: Path | str = None) -> Path:
    if not filename:
        return path_llm() / 'athena'
    return path_llm() / 'athena' / filename

def save_llm_athena(file_sql: str, contents: str) -> Path:
    return Path(write_text(contents, path_llm_athena(file_sql)))

#-----------------------------------------------------------------------------
# Read/Write Text
#-----------------------------------------------------------------------------
def read_text(text_file: Path | str, encoding: str = 'UTF-8') -> str:
    """
    Read text from file
    :param text_file: absolute path to file
    :param encoding: provided file's encoding
    :return: file text contents
    """
    with m_open(file=text_file, encoding=encoding) as t_file:
        return t_file.read()

def write_text(contents: str, file_path: Path | str, encoding: str = 'UTF-8') -> Path:
    """
    Write file contents
    :param contents: string contents
    :param file_path: absolute path of target file
    :param encoding: provided file's encoding
    :return: text_file name
    """
    with m_open(file=file_path, mode='w', encoding=encoding) as f:
        f.write(contents)
        f.close()
        return Path(file_path)

def write_lines(contents: list[str], file_path: Path | str, encoding: str = 'UTF-8') -> Path:
    """
    Write a list of strings to a file, one string per line.

    Returns the path to the file written.
    """
    with m_open(file=file_path, mode='w', encoding=encoding) as f:
        for line in contents:
            f.write(line.rstrip("\n") + "\n")
    return Path(file_path)

def m_open(**kwargs):
    """
    Wrapper for built in open with exception handling and logging
    :return: file like object
    """
    try:
        return open(**kwargs)
    except Exception:
        print('m_open raised an exception', exc_info=True)
        raise

#-----------------------------------------------------------------------------
# Read/Write JSON
#-----------------------------------------------------------------------------
def read_json(json_file: Path | str, encoding: str = 'UTF-8') -> Dict[Any, Any]:
    """
    Read json from file
    :param json_file: absolute path to file
    :param encoding: provided file's encoding
    :return: json file contents
    """
    with m_open(file=json_file, encoding=encoding) as j_file:
        return json.load(j_file)

def write_json(contents: Dict[Any, Any], json_file_path: Path | str, encoding: str = 'UTF-8') -> Path:
    """
    Write JSON to file
    :param contents: json (dict) contents
    :param json_file_path: absolute destination file path
    :param encoding: provided file's encoding
    :return: file name
    """
    directory = os.path.dirname(json_file_path)
    os.makedirs(directory, exist_ok=True)
    with m_open(file=json_file_path, mode='w', encoding=encoding) as f:
        json.dump(contents, f, indent=4)
        return Path(json_file_path)

#-----------------------------------------------------------------------------
# filename to variable (tablespace) name
#-----------------------------------------------------------------------------
def file_to_simplename(filename: Path | str) -> str:
    """
    Get variable name for file
    :return: return simplified variable name for a filepath
    """
    name_part = filename.name if isinstance(filename, Path) else filename
    return name_part.split('.')[0]
