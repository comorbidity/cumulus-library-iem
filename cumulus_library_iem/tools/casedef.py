import csv
from pathlib import Path
from cumulus_library_iem.tools.settings import ENCOUNTER_REF
from cumulus_library_iem.tools import manifest, template, filetool

def make_cohort() -> list[Path]:
    return [copy_template('cohort_casedef.sql')]

def make_cohort_candidate() -> list[Path]:
    criteria_list = ['candidate', 'exclude', 'include']
    return [copy_template(f'cohort_casedef_{rule}.sql') for rule in criteria_list]

def make_cohort_aspects() -> list[Path]:
    aspect_list = ['dx', 'lab', 'proc', 'rx']
    return [copy_template(f'cohort_casedef_{aspect}.sql') for aspect in aspect_list]

def make_timeline() -> list[Path]:
    """
    Make a timeline with ALL variables represented in WIDE (tabular) format *with*
    the Case Definition and rich study population encounter metadata.

    see also:
    * cohort_casedef.sql
    * cohort_variable_wide.sql
    * cohort_study_population_enc.sql
    """
    return [copy_template(f'cohort_timeline.sql')]

#-----------------------------------------------------------------------------
# Template Helpers
#-----------------------------------------------------------------------------
def casedef_columns() -> list[str]:
    """
    :return: ['subtype','system','code','display','tier']
    """
    with open(filetool.path_spreadsheet('casedef.csv'), newline='', encoding='utf-8-sig') as f:
        return next(csv.reader(f), [])

def copy_template(template_sql:str) -> Path:
    return template.copy(template_sql,
                         casedef_columns=casedef_columns(),
                         encounter_ref=ENCOUNTER_REF)

#-----------------------------------------------------------------------------
# Make
#-----------------------------------------------------------------------------
def make() -> list[Path]:
    rules_files = make_cohort_candidate()
    cohort_files = make_cohort()
    aspect_files = make_cohort_aspects()
    timeline_files = make_timeline()

    actions = [
        manifest.FileAction([f'../spreadsheet/file_upload_casedef.toml']),
        manifest.SqlAction(rules_files, 'filter include/exclude', 'build:serial'),
        manifest.SqlAction(cohort_files, 'cohort from case definition (valueset_casedef)'),
        manifest.SqlAction(aspect_files, 'cohort for case definition aspects (dx, rx, lab, proc)'),
        manifest.SqlAction(timeline_files, 'timeline for casedef with variables'),
    ]

    return [manifest.save_actions_toml(actions, 'casedef.toml')]

if __name__ == '__main__':
    for target in make():
        print(target)
