from pathlib import Path
from rapid_elastic import pipeline
from cumulus_library_iem.tools import filetool

#-----------------------------------------------------------------------------
# make
#-----------------------------------------------------------------------------
def make() -> list[Path]:
    query_topics = filetool.path_spreadsheet('query_topics.tsv')
    return pipeline.pipe_batch(query_topics)

if __name__ == '__main__':
    for output_toml in make():
        print(output_toml)
