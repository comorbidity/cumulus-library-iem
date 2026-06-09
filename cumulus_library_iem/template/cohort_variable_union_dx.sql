CREATE TABLE {{ prefix }}__cohort_variable_union_dx AS
SELECT DISTINCT
        var.variable,
        var.code,
        var.display,
        var.system,
        dx.*
FROM    {{ prefix }}__cohort_variable_union         AS var
JOIN    {{ prefix }}__cohort_study_population_dx    AS dx
ON      var.resource_ref = dx.condition_ref
AND     var.system = dx.dx_system
AND     var.code = dx.dx_code
WHERE   var.variable IN
(
 {{ variable_list }}
);