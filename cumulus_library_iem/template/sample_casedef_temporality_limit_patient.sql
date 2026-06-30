CREATE TABLE    {{ prefix }}__sample_casedef_{{ temporality }}_limit_patient_{{ limit }} AS
WITH
patient_list AS (
    SELECT  DISTINCT
            subject_ref
    FROM    {{ prefix }}__sample_casedef_{{ temporality }}
    limit   {{ limit }}
)
SELECT  DISTINCT
        note.*
FROM    {{ prefix }}__sample_casedef_{{ temporality }} as note
JOIN    patient_list AS p
ON      p.subject_ref = note.subject_ref
ORDER BY
        subject_ref,
        enc_period_ordinal,
        note_ordinal;