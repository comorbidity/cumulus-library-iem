create table {{ prefix }}__elastic_union as
with select_union as
(
{{ select_union }}
)
select  distinct *
from    select_union
;

