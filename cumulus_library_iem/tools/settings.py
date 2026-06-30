import os

ENCOUNTER_REF = os.environ.get("CUMULUS_ENCOUNTER_REF", "encounter_ref_link")
CUBE_AS_VIEW = int(os.environ.get("CUMULUS_CUBE_AS_VIEW") or 0)
CUBE_MIN_SUBJECTS = int(os.environ.get("CUMULUS_CUBE_MIN_SUBJECTS") or 10)

# print('###########################################################')
# print('[Settings]')
# print()
# print('Optional: Use VIEW instead of TABLE')
# print('CUMULUS_CUBE_AS_VIEW', '=', CUMULUS_CUBE_AS_VIEW)
# print()
# print('Optional: Minimum number of patients per set size in CUBE data')
# print('CUMULUS_CUBE_MIN_SUBJECTS', '=', CUMULUS_CUBE_MIN_SUBJECTS)
# print()
# print('Optional: Elastic search resluts (output) ')
# print('ELASTIC_OUTPUT', '=', ELASTIC_OUTPUT)
# print()
# print('###########################################################')
