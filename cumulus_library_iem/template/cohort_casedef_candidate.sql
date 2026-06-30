CREATE TABLE {{ prefix }}__cohort_casedef_candidate AS
WITH population AS (
    SELECT 'casedef_dx'     AS valueset,
            dx_system       AS system,
            dx_code         AS code,
            condition_ref   AS resource_ref,
            subject_ref,
            {{ encounter_ref }}
    FROM    {{ prefix }}__cohort_study_population_dx
    WHERE   dx_system       IS NOT NULL
    AND     dx_code         IS NOT NULL
    UNION ALL
    SELECT 'casedef_rx'             AS valueset,
            rx_system               AS system,
            rx_code                 AS code,
            medicationrequest_ref   AS resource_ref,
            subject_ref,
            {{ encounter_ref }}
    FROM    {{ prefix }}__cohort_study_population_rx
    WHERE   rx_system       IS NOT NULL
    AND     rx_code         IS NOT NULL
    UNION ALL
    SELECT 'casedef_proc'   AS valueset,
            proc_system     AS system,
            proc_code       AS code,
            procedure_ref   AS resource_ref,
            subject_ref,
            {{ encounter_ref }}
    FROM    {{ prefix }}__cohort_study_population_proc
    WHERE   proc_system       IS NOT NULL
    AND     proc_code         IS NOT NULL
    UNION ALL
    SELECT 'casedef_lab'            AS valueset,
            lab_observation_system  AS system,
            lab_observation_code    AS code,
            observation_ref         AS resource_ref,
            subject_ref,
            {{ encounter_ref }}
    FROM    {{ prefix }}__cohort_study_population_lab
    WHERE   lab_observation_system  IS NOT NULL
    AND     lab_observation_code    IS NOT NULL
    UNION ALL
    SELECT 'casedef_diag'       AS valueset,
            diag_system         AS system,
            diag_code           AS code,
            diagnosticreport_ref AS resource_ref,
            subject_ref,
            {{ encounter_ref }}
    FROM    {{ prefix }}__cohort_study_population_diag
    WHERE   diag_system       IS NOT NULL
    AND     diag_code         IS NOT NULL
    UNION ALL
    SELECT 'casedef_doc'            AS valueset,
            doc_type_system         AS system,
            doc_type_code           AS code,
            documentreference_ref   AS resource_ref,
            subject_ref,
            {{ encounter_ref }}
    FROM    {{ prefix }}__cohort_study_population_doc
    WHERE   doc_type_system IS NOT NULL
    AND     doc_type_code   IS NOT NULL
),
population_distinct AS (
    SELECT DISTINCT valueset, system, code, resource_ref, subject_ref, {{ encounter_ref }}
    FROM population
)
SELECT  p.valueset,
        casedef.*,
        p.resource_ref,
        p.subject_ref,
        p.{{ encounter_ref }}
FROM    population_distinct     AS p
JOIN    {{ prefix }}__valueset_casedef  AS casedef
        ON  casedef.system = p.system
        AND casedef.code   = p.code