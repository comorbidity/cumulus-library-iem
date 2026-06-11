from pathlib import Path
from cumulus_library_iem.tools import (
    study_meta,
    study_population,
    study_variable,
    study_variable_wide,
    elastic_output,
    cube_study
)

def make_study() -> list[Path]:
    return (study_meta.make() +
            study_population.make() +
            study_variable.make() +
            study_variable_wide.make() +
            # casedef.make() +
            # sample.make() +
            elastic_output.make() +
            cube_study.make())

if __name__ == '__main__':
    for manifest_toml in make_study():
        print(manifest_toml)
