from pathlib import Path
from cumulus_library_iem.tools import manifest, template, filetool, tablespace

def make_cohort() -> list[Path]:
    return [template.copy('cohort_casedef.sql')]

def make_cohort_candidate() -> list[Path]:
    out = list()
    for rule in ['candidate', 'exclude', 'include']:
        file= f'cohort_casedef_{rule}.sql'
        dest = tablespace.name_prefix(file)
        path = filetool.path_athena(dest)

        if path.exists():
            out.append(path)
        else:
            out.append(template.copy(file))
    return out

def make_cohort_aspects(casedef_meta='') -> list[Path]:
    """
    Make cohorts for each case definition aspect [dx, rx, lab, proc].
    Default= one table for each [dx, rx, lab, proc]
    :param casedef_meta: optionally include "casedef.subtype" or other study specific case definition metadata.
    :return: list of file.sql
    """
    # Default aspects using the templates that join study_population_$aspect.
    aspect_list = ['dx', 'lab', 'proc', 'rx']
    return [template.copy(f'cohort_casedef_{aspect}.sql', casedef_meta=casedef_meta) for aspect in aspect_list]

def make_timeline() -> list[Path]:
    """
    Make a timeline with ALL variables represented in WIDE (tabular) format *with*
    the Case Definition and rich study population encounter metadata.

    see also:
    * cohort_casedef.sql
    * cohort_variable_wide.sql
    * cohort_study_population_enc.sql

    :return: list of file.sql
    """
    return [template.copy(f'cohort_timeline.sql')]

#-----------------------------------------------------------------------------
# Make
#-----------------------------------------------------------------------------
def make() -> list[Path]:
    rules_files = make_cohort_candidate()
    cohort_files = make_cohort()
    aspect_files = make_cohort_aspects()
    timeline_files = make_timeline()

    sections = [manifest.as_sql_toml(rules_files, 'filter include/exclude', build_type='build:serial'),
                manifest.as_sql_toml(cohort_files, 'cohort from case definition (valueset_casedef)'),
                manifest.as_sql_toml(aspect_files, 'cohort for case definition aspects (dx, rx, lab, proc)'),
                manifest.as_sql_toml(timeline_files, 'timeline for casedef with variables')]

    return [manifest.save_lines_toml(sections, 'casedef.toml')]

if __name__ == '__main__':
    for target in make():
        print(target)


