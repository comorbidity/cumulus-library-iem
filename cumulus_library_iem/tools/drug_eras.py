from typing import List
from pathlib import Path
from cumulus_library_iem.tools import template


def make(append_manifest=False) -> List[Path]:
    """
    `MedicationRequest_dn` templates are a WIP and will be replaced by ETL and/or cumulus-library `BaseTableBuilder`.
    `MedicationRequest` elements such as `doseQuantity` and `validityPeriod` are optional in FHIR spec.

    https://github.com/smart-on-fhir/cumulus/issues/61
    https://github.com/smart-on-fhir/cumulus-library/blob/main/cumulus_library/studies/core/builder_condition.py
    base_templates.get_codeable_concept_denormalize_query
    sql_utils.CodeableConceptConfig

    :param append_manifest: default False, include `MedicationRequest_dn` SQL files in the manifest.toml.
    :return: list of `Path` for manifest.toml or empty list (do not include in manifest.toml make() targets).
    """
    table_list = ['dispense', 'dosage_timing', 'dosage_quantity', 'dosage_route']
    table_list = [f'medicationrequest_dn_{t}.sql' for t in table_list]
    file_list = [template.copy(f) for f in table_list]
    return file_list if append_manifest else list()
