-- B5 ULD inventory integration approved and applied on 18 September 2026.
begin;

alter table "Basic_Carrier_Record"."Carrier_ULD_Inventory"
  add column "Carrier_IATA" varchar(2) not null,
  drop constraint "Carrier_ULD_Inventory_pkey",
  add constraint carrier_uld_inventory_pkey primary key ("Inventory_UUID"),
  add constraint carrier_uld_inventory_owner foreign key ("Carrier_IATA","ULD_ID")
    references "Basic_Carrier_Record"."Carrier_ULD_Specifications"("Carrier_IATA","ULD_ID")
    on update restrict on delete cascade,
  add constraint carrier_uld_inventory_carrier_code check ("ULD_IATA" ~ '^[A-Z0-9]{2}$'),
  add constraint carrier_uld_inventory_serial_start check ("ULD_Serial_Start" ~ '^[0-9]{1,5}$'),
  add constraint carrier_uld_inventory_serial_end check ("ULD_Serial_End" ~ '^[0-9]{1,5}$'),
  add constraint carrier_uld_inventory_range_order check ("ULD_Serial_Start"::integer <= "ULD_Serial_End"::integer),
  add constraint carrier_uld_inventory_unique_range unique ("Carrier_IATA","ULD_ID","ULD_IATA","ULD_Serial_Start","ULD_Serial_End");
alter table "Basic_Carrier_Record"."Carrier_ULD_Inventory" alter column "ULD_IATA" drop default;
create index carrier_uld_inventory_owner_idx on "Basic_Carrier_Record"."Carrier_ULD_Inventory"("Carrier_IATA","ULD_ID");

alter table "Basic_Carrier_Record"."Carrier_ULD_Inventory" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_ULD_Inventory" from public,anon,authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_ULD_Inventory" to authenticated;
create policy uld_inventory_read on "Basic_Carrier_Record"."Carrier_ULD_Inventory" for select to authenticated
  using (private.can_view_carrier_baggage("Carrier_IATA"));
create policy uld_inventory_insert on "Basic_Carrier_Record"."Carrier_ULD_Inventory" for insert to authenticated
  with check (private.can_edit_carrier_details("Carrier_IATA"));
create policy uld_inventory_update on "Basic_Carrier_Record"."Carrier_ULD_Inventory" for update to authenticated
  using (private.can_edit_carrier_details("Carrier_IATA"))
  with check (private.can_edit_carrier_details("Carrier_IATA"));
create policy uld_inventory_delete on "Basic_Carrier_Record"."Carrier_ULD_Inventory" for delete to authenticated
  using (private.can_edit_carrier_details("Carrier_IATA"));
create trigger uld_inventory_carrier_owner before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_ULD_Inventory"
  for each row execute function private.protect_carrier_identifier();

create or replace function "Basic_Carrier_Record".get_carrier_ulds(p_iata text) returns jsonb
language sql stable security invoker set search_path='' as $$
with access as(
  select private.can_view_carrier_baggage(p_iata) as view,private.can_edit_carrier_details(p_iata) as edit
), basic as(
  select b.* from "Basic_Carrier_Record"."Basic_Carrier_Data" b,access a where a.view and b."Carrier_IATA"=p_iata
), rows as(
  select coalesce(jsonb_agg(jsonb_build_object(
    'code',c."ULD_ID",'type',c."ULD_Type",'isCustom',c."Is_Custom",'isDefault',c."ULD_Default",
    'tare',c."ULD_Tare_Weight"::text,'maximum',c."ULD_Max_Weight"::text,'volume',c."ULD_Max_Volume"::text,
    'remarks',coalesce(c."Remarks",''),'inventory',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i."Inventory_UUID"::text,'carrierCode',i."ULD_IATA",'serialStart',i."ULD_Serial_Start",'serialEnd',i."ULD_Serial_End"
    ) order by i."ULD_IATA",i."ULD_Serial_Start",i."ULD_Serial_End") from "Basic_Carrier_Record"."Carrier_ULD_Inventory" i
      where i."Carrier_IATA"=c."Carrier_IATA" and i."ULD_ID"=c."ULD_ID"),'[]'::jsonb)
  ) order by c."ULD_ID"),'[]'::jsonb) as list,
  coalesce(string_agg(to_jsonb(c)::text||c.xmin::text,',' order by c."ULD_ID"),'') as rev
  from "Basic_Carrier_Record"."Carrier_ULD_Specifications" c,access a where a.view and c."Carrier_IATA"=p_iata
), inventory_revision as(
  select coalesce(string_agg(to_jsonb(i)::text||i.xmin::text,',' order by i."ULD_ID",i."ULD_IATA",i."ULD_Serial_Start"),'') as rev
  from "Basic_Carrier_Record"."Carrier_ULD_Inventory" i,access a where a.view and i."Carrier_IATA"=p_iata
), master as(
  select coalesce(jsonb_agg(jsonb_build_object('code',"ULD_ID",'type',"ULD_Type",'tare',"ULD_TARE"::text,
    'maximum',"ULD_Max_Gross_Weight"::text,'volume',coalesce("ULD_Volume"::text,''),'mainDeckOnly',"Main_Deck_Only") order by "ULD_ID"),'[]'::jsonb) as list
  from "Basic_Carrier_Record"."MASTER_ULD_List",access a where a.view
)
select jsonb_build_object('canView',a.view,'canEdit',a.edit,
  'weightUnit',case when b."Carrier_Unit_Weight_KG" and not b."Carrier_Unit_Weight_LB" then 'KG' when b."Carrier_Unit_Weight_LB" and not b."Carrier_Unit_Weight_KG" then 'LB' else '' end,
  'volumeUnit',case when b."Carrier_Unit_Volume_m3" and not b."Carrier_Unit_Volume_ft3" then 'm3' when b."Carrier_Unit_Volume_ft3" and not b."Carrier_Unit_Volume_m3" then 'ft3' else '' end,
  'rows',r.list,'master',m.list,'revision',case when a.view then md5(r.rev||ir.rev||m.list::text||jsonb_build_array(
    b."Carrier_Unit_Weight_KG",b."Carrier_Unit_Weight_LB",b."Carrier_Unit_Volume_m3",b."Carrier_Unit_Volume_ft3")::text) else '' end)
from access a left join basic b on true cross join rows r cross join inventory_revision ir cross join master m;
$$;
revoke all on function "Basic_Carrier_Record".get_carrier_ulds(text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_ulds(text) to authenticated;

create or replace function "Basic_Carrier_Record".save_carrier_ulds(p_iata text,p_revision text,p_rows jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare s jsonb;row jsonb;inventory_row jsonb;k text;v text;
begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501';end if;
perform 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata for update;
if not found then raise exception 'Save B1 units first' using errcode='23514';end if;
perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata for update;
perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory" where "Carrier_IATA"=p_iata for update;
s:="Basic_Carrier_Record".get_carrier_ulds(p_iata);
if p_revision is distinct from s->>'revision' then raise exception 'ULD settings changed' using errcode='40001';end if;
if s->>'weightUnit'='' or s->>'volumeUnit'='' then raise exception 'Save B1 units first' using errcode='23514';end if;
if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>200 then raise exception 'Invalid ULD list' using errcode='22023';end if;
for row in select value from jsonb_array_elements(p_rows) loop
  if jsonb_typeof(row) is distinct from 'object' or jsonb_typeof(row->'isDefault') is distinct from 'boolean'
    or jsonb_typeof(row->'remarks') is distinct from 'string' or char_length(row->>'remarks')>2000
    or jsonb_typeof(row->'inventory') is distinct from 'array' or jsonb_array_length(row->'inventory')>100
    then raise exception 'Invalid ULD entries' using errcode='22023';end if;
  foreach k in array array['tare','maximum','volume'] loop
    v:=row->>k;if v is null or v !~ '^[0-9]+([.][0-9]{1,6})?$' then raise exception 'Invalid ULD value' using errcode='22023';end if;
  end loop;
  if jsonb_typeof(row->'isCustom') is distinct from 'boolean' or coalesce(row->>'code','') !~ '^[A-Z0-9]{3}$'
    or coalesce(row->>'type','') !~ '^[A-Z0-9]{1,3}$' then raise exception 'Invalid ULD Code or Type' using errcode='22023';end if;
  if not (row->>'isCustom')::boolean and not exists(select 1 from "Basic_Carrier_Record"."MASTER_ULD_List" where "ULD_ID"=row->>'code')
    then raise exception 'ULD not in master' using errcode='23503';end if;
  for inventory_row in select value from jsonb_array_elements(row->'inventory') loop
    if jsonb_typeof(inventory_row) is distinct from 'object' or coalesce(inventory_row->>'carrierCode','') !~ '^[A-Z0-9]{2}$'
      or coalesce(inventory_row->>'serialStart','') !~ '^[0-9]{1,5}$' or coalesce(inventory_row->>'serialEnd','') !~ '^[0-9]{1,5}$'
      or (inventory_row->>'serialStart')::integer>(inventory_row->>'serialEnd')::integer
      then raise exception 'Invalid ULD inventory range' using errcode='22023';end if;
  end loop;
end loop;
delete from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata;
insert into "Basic_Carrier_Record"."Carrier_ULD_Specifications"("Carrier_IATA","ULD_ID","ULD_Type","Is_Custom","ULD_Default","ULD_Tare_Weight","ULD_Max_Weight","ULD_Max_Volume","Remarks")
select p_iata,r->>'code',case when (r->>'isCustom')::boolean then r->>'type' else m."ULD_Type" end,
  (r->>'isCustom')::boolean,(r->>'isDefault')::boolean,(r->>'tare')::numeric,(r->>'maximum')::numeric,(r->>'volume')::numeric,nullif(r->>'remarks','')
from jsonb_array_elements(p_rows) r left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=r->>'code';
if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata
  group by "ULD_Type" having count(*) filter(where "ULD_Default")<>1)
  then raise exception 'Choose one default per ULD type' using errcode='23514';end if;
insert into "Basic_Carrier_Record"."Carrier_ULD_Inventory"("Carrier_IATA","ULD_ID","ULD_IATA","ULD_Serial_Start","ULD_Serial_End")
select p_iata,r->>'code',i->>'carrierCode',i->>'serialStart',i->>'serialEnd'
from jsonb_array_elements(p_rows) r cross join lateral jsonb_array_elements(r->'inventory') i;
return "Basic_Carrier_Record".get_carrier_ulds(p_iata);
end $$;
revoke all on function "Basic_Carrier_Record".save_carrier_ulds(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_ulds(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
