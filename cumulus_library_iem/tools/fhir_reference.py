from enum import Enum

#-----------------------------------------------------------------------------
# Aspects
#-----------------------------------------------------------------------------
class Aspect(Enum):
    """
    Aspect is the type of healthcare concept
    Aspect name is the short key or alias
    Aspect value is the fhir resource

    https://docs.smarthealthit.org/cumulus/library/core-study-details.html
    """
    enc = 'encounter'
    dx = 'condition'
    rx = 'medicationrequest'
    lab = 'observation_lab'
    proc = 'procedure'
    doc = 'documentreference'
    diag = 'diagnosticreport'

def list_aspect() -> list[str]:
    return [aspect.name for aspect in Aspect]

def get_aspect(variable_name:str) -> Aspect:
    return Aspect[variable_name.split('_')[0]]

#-----------------------------------------------------------------------------
# Column
#-----------------------------------------------------------------------------
class Column:
    def __init__(self, code:str=None, system:str=None, aspect:str|Aspect= None, resource:str=None, reference:str=None):
        """
        Column is a convention to alias aggregate tables (such as study population) in a uniform way.
        Many FHIR resources have a FHIR CodeableConcept {system, code, display}. SQL Tables typically join many
        FHIR resource types, for example, FHIR condition "dx" and FHIR MedicationRequest "rx".
        In this example, the column names become "dx_code" and "rx_code" to
        differentiate between a Diagnosis code and Medication.

        This conventino is used everywhere and this strongly typed class exists so that IDEs and developer humans can
        show usages and bind to a common naming convention for columns.

        :param code: "column name" usually in the form $aspect_code like `dx_code`
        :param system: "column name" usually in the form $aspect_system like `dx_system`
        :param aspect: "column name" usually in the form $aspect_system like `dx_aspect` `
        :param resource: "column name", default= Aspect.value
        :param reference: "column name", default= Aspect.value and "_ref" like condition_ref
        """
        if not aspect:
            aspect = get_aspect(code)
        if isinstance(aspect, str):
            aspect = get_aspect(aspect)
        if not resource:
            resource = aspect.value
        if not reference:
            reference = f"{resource}_ref"

        # object state
        self.code = code
        self.aspect = aspect
        self.system = system
        self.resource = resource
        self.reference = reference

    def __dict__(self) -> dict:
        return {'code':self.code,
                'system': self.system,
                'aspect': self.aspect.name,
                'resource': self.resource,
                'reference': self.reference}

    def __str__(self):
        return str(self.__dict__())

def get_column(variable_name:str) -> Column:
    """
    Get column metadata for a given variable name.
    ** This function returns the longest match **.

    :param variable_name: name of a variable
    :return: Column type
    """
    match_list = [col.name for col in ColumnEnum if variable_name.startswith(col.name)]
    best_match = max(match_list, key=len)
    return ColumnEnum[best_match].value

#-----------------------------------------------------------------------------
# Column Enum : known supported column types
#-----------------------------------------------------------------------------
class ColumnEnum(Enum):
    diag = Column('diag_code', 'diag_system')
    diag_category = Column('diag_category_code','diag_category_system')
    diag_conclusion = Column('diag_conclusioncode_code','diag_conclusioncode_system')
    doc = Column('doc_type_code', 'doc_type_system')
    dx = Column('dx_code', 'dx_system')
    dx_category = Column('dx_category_code','dx_category_system')
    enc = Column('enc_type_code', 'enc_type_system')
    enc_class = Column('enc_class_code', 'enc_class_system')
    enc_type = Column('enc_type_code', 'enc_type_system')
    enc_servicetype = Column('enc_servicetype_code','enc_servicetype_system')
    enc_priority = Column('enc_priority_code', 'enc_priority_system')
    enc_dischargedisposition = Column('enc_dischargedisposition_code', 'enc_dischargedisposition_system')
    lab = Column('lab_observation_code', 'lab_observation_system', 'lab', 'observation_lab', 'observation_ref')
    lab_interpretation = Column('lab_interpretation_code','lab_interpretation_system')
    proc = Column('proc_code', 'proc_system')
    proc_category = Column('proc_category_code','proc_category_system')
    rx = Column('rx_code', 'rx_system')
    rx_category = Column('rx_category_code','rx_category_system')