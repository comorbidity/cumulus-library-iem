import unittest
import pandas as pd
from pathlib import Path
from cumulus_library_iem.tools import filetool

def is_valid_spreadsheet_file(filepath: str | Path, delimiter: str = ',') -> bool:
    """
    Check if all rows in a CSV file have the same number of columns as the header.

    Uses Pandas which handles quoted fields correctly.

    Args:
        filepath: Path to the CSV file
        delimiter: Field delimiter (default: comma)

    Returns:
        True if all rows match header column count, False otherwise
    """
    try:
        pd.read_csv(filepath, delimiter=delimiter, on_bad_lines='error')
        return True
    except pd.errors.ParserError:
        return False
    except pd.errors.EmptyDataError:
        return True  # Empty data is technically valid
    except FileNotFoundError:
        raise

class TestSpreadsheet(unittest.TestCase):
    def test_valid_column_count(self):
        for f in filetool.list_spreadsheet():
            delimiter = '\t' if f.suffix == '.tsv' else ','
            self.assertTrue(is_valid_spreadsheet_file(f, delimiter), f"{f} was invalid")
