create table {{ prefix }}__cohort_study_population_doc as
select distinct
    doc.docstatus       as doc_status,
    doc.type_code       as doc_type_code,
    doc.type_display    as doc_type_display,
    doc.type_system     as doc_type_system,
    doc.author_day      as doc_author_day,
    doc."date"          as doc_date,
    doc.aux_has_text,
    doc.documentreference_ref,
    study_population.*
from
    {{ prefix }}__cohort_study_population as study_population,
    core__documentreference as doc
where
    study_population.encounter_ref = doc.encounter_ref
;
