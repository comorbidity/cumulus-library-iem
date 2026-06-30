import tomli_w
from pathlib import Path
from functools import lru_cache
from dataclasses import dataclass
from cumulus_library import StudyManifest
from cumulus_library_iem.tools import filetool

#-----------------------------------------------------------------------------
# get study manifest using cumulus library
#-----------------------------------------------------------------------------
@lru_cache(maxsize=1)
def get_manifest(manifest_path: Path | str = None) -> StudyManifest:
    """
    This method encapsulated changes to v6 StudyManifest
    default: filetool.path_project() = "cumulus_library_iem"

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
# TOML action declarations
#-----------------------------------------------------------------------------
@dataclass(frozen=True)
class FileAction:
    """
    Cumulus Library FILE build action type.
    """
    file_list: list[Path] | list[str]
    description: str = ""
    build_type: str = "build:serial"
    folder:str = ""

@dataclass(frozen=True)
class SqlAction:
    """
    Cumulus Library SQL build action.

    `manifest.py` owns the TOML details:
    * SqlAction.file_list becomes the TOML `files` key
    * each file is written as `athena/<filename>`
    * SqlAction.build_type becomes the TOML `type` key
    """
    file_list: list[Path] | list[str]
    description: str = ""
    build_type: str = "build:parallel"
    folder: str = "athena"

@dataclass(frozen=True)
class ExportAction:
    """
    Cumulus Library export action.

    `manifest.py` owns the TOML details:
    * ExportAction.file_list becomes the TOML `tables` key
    * each file stem becomes the exported table name
    * ExportAction.export_type becomes the TOML `type` key
    """
    file_list: list[Path] | list[str]
    description: str = ""
    export_type: str = "export:counts"

#-----------------------------------------------------------------------------
# TOML builders
#-----------------------------------------------------------------------------
def as_sql_toml(actions: SqlAction | list[SqlAction]) -> dict:
    """
    Build a Python dict for SQL action manifests.

    :param actions: SQL build action, or list of SQL build actions
    :return: dict content for `manifest.toml` submanifest
    """
    return as_actions_toml(_as_list(actions))


def as_export_toml(actions: ExportAction | list[ExportAction]) -> dict:
    """
    Build a Python dict for export action manifests.

    :param actions: export action, or list of export actions
    :return: dict content for `manifest.toml` submanifest
    """
    return as_actions_toml(_as_list(actions))


def as_actions_toml(actions: SqlAction | ExportAction | list[SqlAction | ExportAction | dict]) -> dict:
    """
    Build a Python dict for a mixed list of SQL and export actions.

    This is useful when one manifest contains both build and export actions.
    """
    return {"actions": [_action_to_dict(action) for action in _as_list(actions)]}


def as_file_upload_toml(file_list: list[Path]) -> dict:
    """
    Build a Python dict for file-upload manifests.

    :return: dict content for `manifest.toml` submanifest
    """
    tables: dict[str, dict[str, str]] = {}

    for filename in file_list:
        simple = filetool.file_to_simplename(filename.name)
        table_name = simple if "include" in filename.name else f"valueset_{simple}"
        tables[table_name] = {"file": filename.name}

    return {
        "config_type": "file_upload",
        "tables": tables,
    }

#-----------------------------------------------------------------------------
# TOML save helpers
#-----------------------------------------------------------------------------
def save_actions_toml(
    actions: SqlAction | ExportAction | FileAction| list[SqlAction | ExportAction | FileAction],
    toml_file: Path | str,
) -> Path:
    """
    Save a manifest containing a mixed list of SQL and export actions.
    """
    return save_toml(content=as_actions_toml(actions), toml_file=toml_file)


def save_file_upload_toml(file_list: list[Path], toml_file: Path | str) -> Path:
    if not isinstance(toml_file, Path):
        toml_file = filetool.path_spreadsheet(toml_file)
    return save_toml(content=as_file_upload_toml(file_list), toml_file=toml_file)


def save_toml(content: dict | list[dict], toml_file: Path | str) -> Path:
    """
    Serialize Python TOML content with tomli-w and write it to disk.

    Accepts either a single TOML dict or a list of section dicts. Lists are
    merged before serialization so callers can compose sections without ever
    handling raw TOML strings.
    """
    if not isinstance(toml_file, Path):
        toml_file = filetool.path_project(toml_file)

    content = _merge_toml_sections(content) if isinstance(content, list) else content
    return save_text_toml(dumps_toml(content), toml_file)

def save_lines_toml(lines: list[str], toml_file: Path | str) -> Path:
    """
    Legacy escape hatch for callers that already provide literal TOML lines.
    Prefer `save_toml()` or the action-based save helpers for new code.
    """
    if not isinstance(toml_file, Path):
        toml_file = filetool.path_project(toml_file)
    return save_text_toml("\n".join(lines), toml_file)


def save_text_toml(content: str, toml_file: Path | str) -> Path:
    """
    Legacy escape hatch for callers that already provide literal TOML text.
    Prefer `save_toml()` or the action-based save helpers for new code.
    """
    if not isinstance(toml_file, Path):
        toml_file = filetool.path_project(toml_file)
    return filetool.write_text(content.strip() + "\n", toml_file)

#-----------------------------------------------------------------------------
# TOML helpers
#-----------------------------------------------------------------------------
def _clean_description(description: str | None = None) -> str:
    if not description:
        return ""
    return description.replace("[", "(").replace("]", ")")

def path_relative(file_list: list[Path | str], relative_to: str | None = None) -> list[str]:
    return list(_path_relative(file_list=file_list, relative_to=relative_to))

def _path_relative(file_list: list[Path | str], relative_to: str | None = None):
    for filename in file_list:
        if isinstance(filename, Path):
            if relative_to:
                yield f"{relative_to}/{filename.name}"
            else:
                yield filename.name
        if isinstance(filename, str):
            if relative_to:
                yield f"{relative_to}/{filename}"
            else:
                yield filename

def _action_to_dict(action: SqlAction | ExportAction | FileAction | dict) -> dict:

    if isinstance(action, ExportAction):
        return {
            "description": _clean_description(action.description),
            "type": action.export_type or "",
            "tables": [f.stem for f in action.file_list],
        }

    if isinstance(action, SqlAction):
        return {
            "description": _clean_description(action.description),
            "type": action.build_type or "",
            # "files": [f"athena/{f.name}" for f in action.file_list],
            "files": path_relative(action.file_list, action.folder)
        }

    if isinstance(action, FileAction):
        return {
            "description": _clean_description(action.description),
            "type": action.build_type or "",
            # "files": [f for f in action.file_list],
            "files": path_relative(action.file_list, action.folder)
        }

    if isinstance(action, dict):
        return action

def _as_list(item):
    return item if isinstance(item, list) else [item]

def _merge_toml_sections(content: list[dict]) -> dict:
    """
    Merge section dictionaries into one TOML document dictionary.

    Special handling:
    * `actions` lists are concatenated for repeated [[actions]] blocks.
    * `tables` mappings are merged for repeated [tables.*] blocks.
    * scalar keys must not conflict.
    """
    merged: dict = {}

    for section in content:
        for key, value in section.items():
            if key == "actions":
                merged.setdefault("actions", [])
                merged["actions"].extend(value or [])
            elif key == "tables":
                merged.setdefault("tables", {})
                duplicate_tables = set(merged["tables"]).intersection(value or {})
                if duplicate_tables:
                    duplicates = ", ".join(sorted(duplicate_tables))
                    raise ValueError(f"Duplicate TOML table names: {duplicates}")
                merged["tables"].update(value or {})
            elif key not in merged:
                merged[key] = value
            elif merged[key] != value:
                raise ValueError(
                    f"Conflicting TOML value for key {key!r}: "
                    f"{merged[key]!r} != {value!r}"
                )
    return merged

def dumps_toml(content: dict) -> str:
    """
    Serialize TOML via tomli-w rather than hand-quoting strings/lists.
    """
    return tomli_w.dumps(content)