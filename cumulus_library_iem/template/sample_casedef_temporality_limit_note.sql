create TABLE {{ prefix }}__sample_casedef_{{ temporality }}_limit_note_{{ limit }} as
select  distinct
        subject_ref, note_ordinal, days_since, note_ref, group_name
from
        {{ prefix }}__sample_casedef_{{ temporality }}
where
        note_ordinal <= {{ limit }}
order by
        subject_ref, note_ordinal;