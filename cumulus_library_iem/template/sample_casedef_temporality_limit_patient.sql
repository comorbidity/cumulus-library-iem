create TABLE {{ prefix }}__sample_casedef_{{ temporality }}_limit_patient_{{ limit }} as
WITH
patient_list as (
    select  distinct
            subject_ref
    from    {{ prefix }}__sample_casedef_{{ temporality }}
    limit   {{ limit }}
)
select      distinct
            note.*
from        {{ prefix }}__sample_casedef_{{ temporality }} as note,
            patient_list as P
where       P.subject_ref = note.subject_ref
order by    subject_ref,
            enc_period_ordinal,
            note_ordinal;
