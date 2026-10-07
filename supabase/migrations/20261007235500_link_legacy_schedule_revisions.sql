begin;

update "Basic_Carrier_Record"."Flight_Schedule_Imports" child
set "Supersedes_Import_ID"=substring(child."Creator_Reference" from '(?i)^Revision of ([0-9a-f-]{36})$')::uuid
where child."Supersedes_Import_ID" is null
  and coalesce(child."Creator_Reference",'')~*'^Revision of [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists(
    select 1 from "Basic_Carrier_Record"."Flight_Schedule_Imports" parent
    where parent."Import_ID"=substring(child."Creator_Reference" from '(?i)^Revision of ([0-9a-f-]{36})$')::uuid
      and parent."Carrier_IATA"=child."Carrier_IATA"
  );

update "Basic_Carrier_Record"."Flight_Schedule_Imports" parent
set "Status"='SUPERSEDED',"Superseded_At"=coalesce(parent."Superseded_At",now())
where parent."Status"='PUBLISHED'
  and exists(
    select 1 from "Basic_Carrier_Record"."Flight_Schedule_Imports" child
    where child."Supersedes_Import_ID"=parent."Import_ID"
      and child."Carrier_IATA"=parent."Carrier_IATA"
      and child."Status"='PUBLISHED'
  );

with recursive family_tree as(
  select i."Import_ID",i."Import_ID" family_id
  from "Basic_Carrier_Record"."Flight_Schedule_Imports" i
  where i."Supersedes_Import_ID" is null
  union all
  select child."Import_ID",parent.family_id
  from family_tree parent
  join "Basic_Carrier_Record"."Flight_Schedule_Imports" child
    on child."Supersedes_Import_ID"=parent."Import_ID"
)
update "Basic_Carrier_Record"."Flight_Schedule_Imports" i
set "Schedule_Family_ID"=tree.family_id
from family_tree tree
where tree."Import_ID"=i."Import_ID"
  and i."Schedule_Family_ID" is distinct from tree.family_id;

commit;
