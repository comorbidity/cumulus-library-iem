CREATE  TABLE   {{ prefix }}__elastic_union AS
WITH select_union AS
(
{{ select_union }}
)
SELECT  DISTINCT *
FROM    select_union
WHERE   select_union.topic   NOT LIKE '%generic%'
;

