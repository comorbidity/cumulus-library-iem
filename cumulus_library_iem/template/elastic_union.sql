DROP    TABLE
IF      EXISTS  {{ prefix }}__elastic_union;
--
CREATE  TABLE   {{ prefix }}__elastic_union AS
WITH select_union AS
(
{{ select_union }}
)
SELECT  DISTINCT *
FROM    select_union
;

