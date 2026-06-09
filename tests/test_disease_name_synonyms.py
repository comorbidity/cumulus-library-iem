import unittest
from collections import Counter
from cumulus_library_iem.tools import filetool

DISEASE_FILE = filetool.path_project('disease_names.json')
DISEASE_NAMES = filetool.read_json(DISEASE_FILE)

class TestDiseaseNameSynonyms(unittest.TestCase):
    def test_20_diseases(self):
        self.assertTrue(20, len(DISEASE_NAMES.keys()))

    def test_no_duplicates(self):
        for dx in DISEASE_NAMES:
            lower = sorted([name.lower() for name in DISEASE_NAMES[dx]])
            uniq = sorted(set(lower))
            self.assertEqual(len(uniq), len(lower), f'disease name duplicates in: {dx}\t{Counter(lower)}')

    def test_warn_overlap(self):
        syn_list = list()
        for dx in DISEASE_NAMES:
            syn_list+= sorted([name.lower() for name in DISEASE_NAMES[dx]])

        term_freq = Counter(syn_list)

        for query in term_freq:
            if term_freq[query] > 1:
                print('WARN', term_freq[query], 'disease names map to query', f"'{query}'")

    def json_to_csv(self):
        out = list()
        for dx in DISEASE_NAMES:
            for query in DISEASE_NAMES[dx]:
                out.append(f"{dx},{query}")
        out = '\n'.join(out)
        print(out)

        filetool.write_text(out, f"{DISEASE_FILE}.csv")


