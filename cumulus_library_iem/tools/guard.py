import datetime
from enum import Enum
from collections import OrderedDict
from typing import List, Iterable
from fhirclient.models.fhirdate import FHIRDate
from fhirclient.models.coding import Coding

###############################################################################
#
# Type Check (yes/no)
#
###############################################################################
def is_enum(obj) -> bool:
    return isinstance(obj, Enum)

def is_dict(obj) -> bool:
    return isinstance(obj, dict)

def is_list(obj) -> bool:
    return isinstance(obj, list)

def is_list_type(obj, type) -> bool:
    if isinstance(obj, list) and all(isinstance(item, type) for item in obj):
        return True
    return False

###############################################################################
#
# Cast input "as type", fail fast if not possible
#
###############################################################################
def as_range(obj) -> range:
    if isinstance(obj, list):
        return range(obj[0], obj[1])
    if isinstance(obj, tuple):
        return range(obj[0], obj[1])
    if isinstance(obj, range):
        return obj
    Exception(f'as_range failed for {obj}')

def as_coding(obj) -> Coding:
    c = Coding()
    src = obj.__dict__
    c.code = src.get('code')
    c.display = src.get('display')
    c.system = src.get('system')
    return c

def as_list(obj) -> list:
    if isinstance(obj, list):
        return obj
    return [obj]

def as_list_coding(obj) -> List[Coding]:
    obj = as_list(obj)
    if is_list_type(obj, Coding):
        return obj
    return [as_coding(c) for c in list(obj)]

def as_list_str(obj) -> List[str]:
    obj = as_list(obj)
    if is_list_type(obj, str):
        return obj
    return [str(c) for c in list(obj)]

def as_enum_names(enum_list: List[Enum] | Enum | object) -> List[str]:
    if is_enum(enum_list):
        return as_enum_names(list(enum_list))
    return sorted(list(set([entry.name for entry in enum_list])))

def as_enum_values(enum_list: List[Enum] | Enum | object) -> List[str]:
    if is_enum(enum_list):
        return as_enum_values(list(enum_list))
    return sorted(list(set([entry.value for entry in list(enum_list)])))

###############################################################################
#
# Sort / Filter
#
###############################################################################
def filter_list_coding(standard_list: List[Coding] | List, code_list: List[Coding] | List[str]) -> List[Coding]:
    """
    :param standard_list: Standard list of codes from a ValueSet
    :param code_list: List of codes to filter
    :return: List Coding in `standard_list` filtered by `code_list`
    """
    # guard inputs
    standard_list = as_list_coding(standard_list)
    if is_list_type(code_list, Coding):
        code_list = [code.code for code in code_list]
    results = list()
    for standard in standard_list:
        if standard.code in code_list:
            results.append(standard)
    return results

def exclude_list(input_list: list, exclude_list: list) -> list:
    """
    exclude items in `exclude_list` from `input_list`:
    """
    return [item for item in input_list if item not in exclude_list]

def sort_list(unsorted: Iterable) -> list:
    return sorted(list(set(list(unsorted))))

def sort_dict(unsorted: dict) -> OrderedDict:
    return OrderedDict(sorted(unsorted.items()))

###############################################################################
#
# DateTime Safety
#
###############################################################################
def datetime_now(local: bool = False) -> datetime.datetime:
    """
    Current date and time, suitable for use as a FHIR 'instant' data type
    The returned datetime is always 'aware' (not 'naive').
    :param local: whether to use local timezone or (if False) UTC
    """
    now = datetime.datetime.now(datetime.timezone.utc)
    if local:
        now = now.astimezone()
    return now

def parse_fhir_date(yyyy_mm_dd) -> FHIRDate:
    """
    :param yyyy_mm_dd: YEAR Month Date
    :return: FHIR Date with only the date part.
    """
    if yyyy_mm_dd and isinstance(yyyy_mm_dd, FHIRDate):
        return yyyy_mm_dd
    if yyyy_mm_dd and isinstance(yyyy_mm_dd, str):
        if len(yyyy_mm_dd) >= 10:
            yyyy_mm_dd = yyyy_mm_dd[:10]
            return FHIRDate(yyyy_mm_dd)

def parse_date(value: str | None) -> datetime.date | None:
    return parse_datetime(value).date()

def parse_datetime(value: str | None) -> datetime.datetime | None:
    """
    Converts FHIR instant/dateTime/date types into a Python format.

    - This tries to be very graceful - any errors will result in a None return.
    - Missing month/day fields are treated as the earliest possible date (i.e. '1')

    CAUTION: Returned datetime might be naive - which makes more sense for dates without a time.
             The spec says any field with hours/minutes SHALL have a timezone.
             But fields that are just dates SHALL NOT have a timezone.
    """
    if not value:
        return None

    try:
        # Handle partial dates like "1980-12" (which spec allows, but fromisoformat can't handle)
        pieces = value.split("-")
        if len(pieces) == 1:
            return datetime.datetime(int(pieces[0]), 1, 1)  # note: naive datetime
        elif len(pieces) == 2:
            return datetime.datetime(int(pieces[0]), int(pieces[1]), 1)  # note: naive datetime

        # Until we depend on Python 3.11+, manually handle Z
        value = value.replace("Z", "+00:00")

        return datetime.datetime.fromisoformat(value)
    except ValueError:
        return None
