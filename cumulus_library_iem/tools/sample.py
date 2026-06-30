from pathlib import Path
from cumulus_library_iem.tools.settings import ENCOUNTER_REF
from cumulus_library_iem.tools import filetool, template, tablespace, manifest
from cumulus_library_iem.tools.study_variable import Aspect, list_aspect_names

########################################################################################################
# Encounter timing relative to "1st casedef match"
#
# pre = before
# peri = during
# peri_post = during or after
# post = after
##########################################################################################################
TEMPORALITY = ['pre', 'peri', 'peri_post', 'post']

########################################################################################################
# Step 1: sample_casedef
##########################################################################################################
def make_sample() -> list[Path]:
    return [template.copy('sample_casedef.sql', encounter_ref=ENCOUNTER_REF)]

########################################################################################################
# Step 2: for each Aspect
##########################################################################################################
def make_aspect() -> list[Path]:
    return [_make_aspect(aspect) for aspect in list_aspect_names()]

def _make_aspect(aspect: Aspect | str) -> Path:
    """
    Intended use:
    * Aspect.dx:    sample casedef notes that have an encounter matching 1+ "dx" study variable(s)
                    Validate if case definition was "first" kidney transplant.
    * Aspect.rx:    sample casedef notes that have an encounter matching 1+ "rx" study variable(s)
                    Validate medications were active/stopped/etc
    * Aspect.lab:   sample casedef notes that have an encounter matching 1+ "lab" study variable(s)
                    Validate lab values

    :param aspect: name of aspect to sample
    :return: path to Athena SQL
    """
    if isinstance(aspect, Aspect):
        return _make_aspect(aspect.name)
    content = template.load('sample_casedef_aspect.sql', aspect=aspect, encounter_ref=ENCOUNTER_REF)
    table = tablespace.name_prefix(f'sample_casedef_{aspect}')
    path = filetool.path_athena(f'{table}.sql')
    return filetool.save_athena(path, content)

########################################################################################################
# Step 3: for each TEMPORALITY
##########################################################################################################
def make_temporality() -> list[Path]:
    template_name = 'sample_casedef_temporality'
    return [_make_temporality(template_name, temporality) for temporality in TEMPORALITY]

########################################################################################################
# Step 4: with sample size limits
##########################################################################################################
def make_temporality_limit_patient(limit: int = 10) -> list[Path]:
    template_name = 'sample_casedef_temporality_limit_patient'
    return [_make_temporality(template_name, temporality, limit) for temporality in TEMPORALITY]

def make_temporality_limit_note(limit: int = 50) -> list[Path]:
    template_name = 'sample_casedef_temporality_limit_note'
    return [_make_temporality(template_name, temporality, limit) for temporality in TEMPORALITY]

def _make_temporality(template_name:str, temporality:str, limit: int = None) -> Path:
    """
    :param template_name: name of the SQL template to load
    :param temporality: str one of ['pre', 'peri', 'peri_post', 'post']
    :param limit: int patients or notes in sample
    :return: path to Athena SQL
    """
    table_name = template_name.replace('temporality', temporality)

    if limit:
        limit = str(limit)
        table_name = f'{table_name}_{limit}'
    else:
        limit = ''
    text = template.load(f'{template_name}.sql',
                         encounter_ref=ENCOUNTER_REF,
                         temporality=temporality,
                         limit=limit)
    target_table = tablespace.name_prefix(table_name)
    target_file = filetool.path_athena(f'{target_table}.sql')
    return Path(filetool.write_text(text, target_file))

def make_sample_task() -> list[Path]:
    task = ['ibd__sample_task.sql',
            'ibd__sample_task_aspect.sql',
            'ibd__sample_task_tier.sql']
    return [filetool.path_athena(t) for t in task]

#-----------------------------------------------------------------------------
# Make
#-----------------------------------------------------------------------------
def make() -> list[Path]:
    aspect_list = list_aspect_names()

    actions = [
        manifest.SqlAction(make_sample(), 'sample_casedef (all)'),
        manifest.SqlAction(make_aspect(), f'sample for aspects {aspect_list}'),
        manifest.SqlAction(make_temporality(), f'sample temporality {TEMPORALITY}'),
        manifest.SqlAction(make_temporality_limit_patient(10), 'sample size limit patients'),
        manifest.SqlAction(make_temporality_limit_note(50), 'sample size limit notes'),
        manifest.SqlAction(make_sample_task(), 'sample task', "build:serial"),
    ]

    return [manifest.save_actions_toml(actions, 'sample.toml')]

if __name__ == '__main__':
    for target in make():
        print(target)


