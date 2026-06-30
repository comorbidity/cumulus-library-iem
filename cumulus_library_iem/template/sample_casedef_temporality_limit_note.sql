CREATE TABLE {{ prefix }}__sample_casedef_{{ temporality }}_limit_note_{{ limit }} as
SELECT  DISTINCT
        subject_ref, note_ordinal, days_since, note_ref, group_name
FROM
        {{ prefix }}__sample_casedef_{{ temporality }}
WHERE
        note_ordinal <= {{ limit }}
ORDER BY
        subject_ref, note_ordinal;