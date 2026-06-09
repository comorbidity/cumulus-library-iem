CREATE TABLE {{ prefix }}__exclude_casedef AS
-- Optional: user defined exclusions
SELECT
    cast(NULL as varchar) as subject_ref,
    cast(NULL as varchar) as encounter_ref,
    cast(NULL as varchar) as exclude_reason,
    cast(NULL as varchar) as fhir_resource
WHERE FALSE;