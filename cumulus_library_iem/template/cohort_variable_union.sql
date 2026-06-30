CREATE  TABLE   {{ prefix }}__cohort_variable_union AS
WITH
select_union AS
(
{{ select_union }}
),
-- Collapse semantically identical evidence rows before joining to the
-- encounter spine. The evidence key is variable + coding + resource +
-- retained encounter link. ``display`` is descriptive metadata, not part
-- of the evidence identity, valuesets can legitimately carry more than
-- one display string for the same system/code.
evidence_distinct AS
(
    SELECT  select_union.variable,
            select_union.code,
            MAX(CAST(select_union.display AS VARCHAR)) AS display,
            select_union.system,
            select_union.resource_ref,
            select_union.{{ encounter_ref }}
    FROM    select_union
    GROUP BY
            select_union.variable,
            select_union.code,
            select_union.system,
            select_union.resource_ref,
            select_union.{{ encounter_ref }}
)
SELECT  DISTINCT
        evidence_distinct.variable,
        evidence_distinct.code,
        evidence_distinct.display,
        evidence_distinct.system,
        evidence_distinct.resource_ref,
        evidence_distinct.{{ encounter_ref }},
        sp.subject_ref,
        sp.status,
        sp.age_at_visit,
        sp.age_group,
        sp.gender,
        sp.race_display,
        sp.ethnicity_display,
        sp.enc_period_ordinal,
        sp.enc_period_start_day,
        sp.enc_period_end_day,
        sp.enc_class_code,
        sp.enc_class_display,
        sp.enc_type_system,
        sp.enc_type_code,
        sp.enc_type_display,
        sp.enc_servicetype_system,
        sp.enc_servicetype_code,
        sp.enc_servicetype_display
FROM    evidence_distinct
JOIN    {{ prefix }}__cohort_study_population AS sp
ON      evidence_distinct.{{ encounter_ref }} = sp.encounter_ref
;
