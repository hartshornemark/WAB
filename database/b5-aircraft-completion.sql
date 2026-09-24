-- B5 becomes aircraft-specific and gains an explicit applicability decision.
begin;

alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications"
  add column "Aircraft_Type_IATA" varchar(3),
  add column "Aircraft_Series_Subtype" varchar(4);
update "Basic_Carrier_Record"."Carrier_ULD_Specifications" c set
  "Aircraft_Type_IATA"=(select b."Aircraft_Type_IATA" from "Basic_Carrier_Record"."Basic_Aircraft_Data" b where b."Carrier_IATA"=c."Carrier_IATA" order by b."Aircraft_Type_IATA",b."Aircraft_Series_Subtype" limit 1),
  "Aircraft_Series_Subtype"=(select b."Aircraft_Series_Subtype" from "Basic_Carrier_Record"."Basic_Aircraft_Data" b where b."Carrier_IATA"=c."Carrier_IATA" order by b."Aircraft_Type_IATA",b."Aircraft_Series_Subtype" limit 1);
do $$begin if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Aircraft_Type_IATA" is null or "Aircraft_Series_Subtype" is null) then raise exception 'Every existing carrier ULD requires an aircraft identity before B5 can become aircraft-specific';end if;end$$;
set constraints all immediate;

alter table "Basic_Carrier_Record"."Carrier_ULD_Inventory"
  add column "Aircraft_Type_IATA" varchar(3),
  add column "Aircraft_Series_Subtype" varchar(4);
update "Basic_Carrier_Record"."Carrier_ULD_Inventory" i set
  "Aircraft_Type_IATA"=s."Aircraft_Type_IATA","Aircraft_Series_Subtype"=s."Aircraft_Series_Subtype"
from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s where s."Carrier_IATA"=i."Carrier_IATA" and s."ULD_ID"=i."ULD_ID";

alter table "Basic_Carrier_Record"."Carrier_ULD_Inventory" drop constraint carrier_uld_inventory_owner,drop constraint carrier_uld_inventory_unique_range;
alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications" drop constraint "Carrier_ULD_Specifications_pkey";
alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications"
  alter column "Aircraft_Type_IATA" set not null,alter column "Aircraft_Series_Subtype" set not null,
  add constraint carrier_uld_specifications_pkey primary key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID"),
  add constraint carrier_uld_specifications_aircraft_fk foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update restrict on delete cascade;
alter table "Basic_Carrier_Record"."Carrier_ULD_Inventory"
  alter column "Aircraft_Type_IATA" set not null,alter column "Aircraft_Series_Subtype" set not null,
  add constraint carrier_uld_inventory_owner foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID") references "Basic_Carrier_Record"."Carrier_ULD_Specifications"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID") on update restrict on delete cascade,
  add constraint carrier_uld_inventory_unique_range unique("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID","ULD_IATA","ULD_Serial_Start","ULD_Serial_End");

create table "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings"(
 "Carrier_IATA" varchar(2) not null,"Aircraft_Type_IATA" varchar(3) not null,"Aircraft_Series_Subtype" varchar(4) not null,
 "Utilises_ULDs" boolean not null default false,"Updated_At" timestamptz not null default now(),
 primary key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
 foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update restrict on delete cascade
);
insert into "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Utilises_ULDs")
select distinct "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",true from "Basic_Carrier_Record"."Carrier_ULD_Specifications";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" from public,anon,authenticated;
grant select,insert,update on "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" to authenticated;
create policy b5_settings_read on "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" for select to authenticated using(private.can_view_carrier_baggage("Carrier_IATA"));
create policy b5_settings_insert on "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" for insert to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy b5_settings_update on "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" for update to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));

create or replace function private.check_uld_defaults() returns trigger language plpgsql set search_path='' as $$
declare iata text;atype text;subtype text;begin if tg_op='DELETE' then iata:=old."Carrier_IATA";atype:=old."Aircraft_Type_IATA";subtype:=old."Aircraft_Series_Subtype";else iata:=new."Carrier_IATA";atype:=new."Aircraft_Type_IATA";subtype:=new."Aircraft_Series_Subtype";end if;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=iata and "Aircraft_Type_IATA"=atype and "Aircraft_Series_Subtype"=subtype group by "ULD_Type" having count(*) filter(where "ULD_Default")<>1) then raise exception 'Choose exactly one default for each adopted ULD type' using errcode='23514';end if;return null;end$$;

create function "Basic_Carrier_Record".get_carrier_ulds(p_iata text,p_type text,p_subtype text) returns jsonb language sql stable security invoker set search_path='' as $$
with access as(select private.can_view_carrier_baggage(p_iata) view,private.can_edit_carrier_details(p_iata) edit),
basic as(select b.* from "Basic_Carrier_Record"."Basic_Carrier_Data" b,access a where a.view and b."Carrier_IATA"=p_iata),
aircraft as(select a.* from "Basic_Carrier_Record"."Basic_Aircraft_Data" a,access x where x.view and a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=p_type and a."Aircraft_Series_Subtype"=p_subtype),
settings as(select coalesce((select "Utilises_ULDs" from "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype),false) utilises,coalesce((select to_jsonb(s)::text||s.xmin::text from "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" s where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=p_type and s."Aircraft_Series_Subtype"=p_subtype),'') rev),
rows as(select coalesce(jsonb_agg(jsonb_build_object('code',c."ULD_ID",'type',c."ULD_Type",'isCustom',c."Is_Custom",'isDefault',c."ULD_Default",'tare',c."ULD_Tare_Weight"::text,'maximum',c."ULD_Max_Weight"::text,'volume',c."ULD_Max_Volume"::text,'remarks',coalesce(c."Remarks",''),'inventory',coalesce((select jsonb_agg(jsonb_build_object('id',i."Inventory_UUID"::text,'carrierCode',i."ULD_IATA",'serialStart',i."ULD_Serial_Start",'serialEnd',i."ULD_Serial_End") order by i."ULD_IATA",i."ULD_Serial_Start") from "Basic_Carrier_Record"."Carrier_ULD_Inventory" i where i."Carrier_IATA"=c."Carrier_IATA" and i."Aircraft_Type_IATA"=c."Aircraft_Type_IATA" and i."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype" and i."ULD_ID"=c."ULD_ID"),'[]'::jsonb)) order by c."ULD_ID"),'[]'::jsonb) list,coalesce(string_agg(to_jsonb(c)::text||c.xmin::text,',' order by c."ULD_ID"),'') rev from "Basic_Carrier_Record"."Carrier_ULD_Specifications" c,access a where a.view and c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=p_type and c."Aircraft_Series_Subtype"=p_subtype),
irev as(select coalesce(string_agg(to_jsonb(i)::text||i.xmin::text,',' order by i."ULD_ID",i."ULD_IATA",i."ULD_Serial_Start"),'') rev from "Basic_Carrier_Record"."Carrier_ULD_Inventory" i,access a where a.view and i."Carrier_IATA"=p_iata and i."Aircraft_Type_IATA"=p_type and i."Aircraft_Series_Subtype"=p_subtype),
master as(select coalesce(jsonb_agg(jsonb_build_object('code',"ULD_ID",'type',"ULD_Type",'tare',"ULD_TARE"::text,'maximum',"ULD_Max_Gross_Weight"::text,'volume',coalesce("ULD_Volume"::text,''),'mainDeckOnly',"Main_Deck_Only") order by "ULD_ID"),'[]'::jsonb) list from "Basic_Carrier_Record"."MASTER_ULD_List",access a where a.view)
select jsonb_build_object('canView',a.view and ac."Aircraft_Type_IATA" is not null,'canEdit',a.edit,'aircraftType',coalesce(ac."Aircraft_Type_IATA",''),'aircraftSubtype',coalesce(ac."Aircraft_Series_Subtype",''),'utilisesUlds',st.utilises,'weightUnit',case when b."Carrier_Unit_Weight_KG" and not b."Carrier_Unit_Weight_LB" then 'KG' when b."Carrier_Unit_Weight_LB" and not b."Carrier_Unit_Weight_KG" then 'LB' else '' end,'volumeUnit',case when b."Carrier_Unit_Volume_m3" and not b."Carrier_Unit_Volume_ft3" then 'm3' when b."Carrier_Unit_Volume_ft3" and not b."Carrier_Unit_Volume_m3" then 'ft3' else '' end,'rows',r.list,'master',m.list,'revision',case when a.view then md5(r.rev||ir.rev||st.rev||m.list::text||jsonb_build_array(b."Carrier_Unit_Weight_KG",b."Carrier_Unit_Weight_LB",b."Carrier_Unit_Volume_m3",b."Carrier_Unit_Volume_ft3")::text) else '' end) from access a left join basic b on true left join aircraft ac on true cross join settings st cross join rows r cross join irev ir cross join master m;
$$;

create function "Basic_Carrier_Record".save_carrier_uld_applicability(p_iata text,p_type text,p_subtype text,p_revision text,p_utilises boolean) returns jsonb language plpgsql security invoker set search_path='' as $$declare s jsonb;begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501';end if;
perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;if not found then raise exception 'Aircraft unavailable' using errcode='23503';end if;
perform 1 from "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
s:="Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);if p_revision is distinct from s->>'revision' then raise exception 'ULD settings changed' using errcode='40001';end if;
insert into "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" values(p_iata,p_type,p_subtype,p_utilises,now()) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "Utilises_ULDs"=excluded."Utilises_ULDs","Updated_At"=now();
return "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);end$$;

create function "Basic_Carrier_Record".save_carrier_ulds(p_iata text,p_type text,p_subtype text,p_revision text,p_rows jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$declare s jsonb;row jsonb;inventory_row jsonb;k text;v text;begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501';end if;
perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;if not found then raise exception 'Aircraft unavailable' using errcode='23503';end if;
perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
s:="Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);if p_revision is distinct from s->>'revision' then raise exception 'ULD settings changed' using errcode='40001';end if;if not (s->>'utilisesUlds')::boolean then raise exception 'B5 is skipped' using errcode='23514';end if;if s->>'weightUnit'='' or s->>'volumeUnit'='' then raise exception 'Save B1 units first' using errcode='23514';end if;
if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>200 then raise exception 'At least one ULD Type is required' using errcode='23514';end if;
for row in select value from jsonb_array_elements(p_rows) loop
 if jsonb_typeof(row) is distinct from 'object' or jsonb_typeof(row->'isDefault') is distinct from 'boolean' or jsonb_typeof(row->'remarks') is distinct from 'string' or char_length(row->>'remarks')>2000 or jsonb_typeof(row->'inventory') is distinct from 'array' or jsonb_array_length(row->'inventory')>100 then raise exception 'Invalid ULD entries' using errcode='22023';end if;
 foreach k in array array['tare','maximum','volume'] loop v:=row->>k;if v is null or v !~ '^[0-9]+([.][0-9]{1,6})?$' then raise exception 'Invalid ULD value' using errcode='22023';end if;end loop;
 if jsonb_typeof(row->'isCustom') is distinct from 'boolean' or coalesce(row->>'code','') !~ '^[A-Z0-9]{3}$' or coalesce(row->>'type','') !~ '^[A-Z0-9]{1,3}$' then raise exception 'Invalid ULD Code or Type' using errcode='22023';end if;
 if not (row->>'isCustom')::boolean and not exists(select 1 from "Basic_Carrier_Record"."MASTER_ULD_List" where "ULD_ID"=row->>'code') then raise exception 'ULD not in master' using errcode='23503';end if;
 for inventory_row in select value from jsonb_array_elements(row->'inventory') loop if jsonb_typeof(inventory_row) is distinct from 'object' or coalesce(inventory_row->>'carrierCode','') !~ '^[A-Z0-9]{2}$' or coalesce(inventory_row->>'serialStart','') !~ '^[0-9]{1,5}$' or coalesce(inventory_row->>'serialEnd','') !~ '^[0-9]{1,5}$' or (inventory_row->>'serialStart')::integer>(inventory_row->>'serialEnd')::integer then raise exception 'Invalid ULD inventory range' using errcode='22023';end if;end loop;
end loop;
delete from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype;
insert into "Basic_Carrier_Record"."Carrier_ULD_Specifications"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID","ULD_Type","Is_Custom","ULD_Default","ULD_Tare_Weight","ULD_Max_Weight","ULD_Max_Volume","Remarks") select p_iata,p_type,p_subtype,r->>'code',case when (r->>'isCustom')::boolean then r->>'type' else m."ULD_Type" end,(r->>'isCustom')::boolean,(r->>'isDefault')::boolean,(r->>'tare')::numeric,(r->>'maximum')::numeric,(r->>'volume')::numeric,nullif(r->>'remarks','') from jsonb_array_elements(p_rows) r left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=r->>'code';
if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype group by "ULD_Type" having count(*) filter(where "ULD_Default")<>1) then raise exception 'Choose one default per ULD type' using errcode='23514';end if;
insert into "Basic_Carrier_Record"."Carrier_ULD_Inventory"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID","ULD_IATA","ULD_Serial_Start","ULD_Serial_End") select p_iata,p_type,p_subtype,r->>'code',i->>'carrierCode',lpad(i->>'serialStart',5,'0'),lpad(i->>'serialEnd',5,'0') from jsonb_array_elements(p_rows) r cross join lateral jsonb_array_elements(r->'inventory') i;
return "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);end$$;

drop function "Basic_Carrier_Record".save_carrier_ulds(text,text,jsonb);
drop function "Basic_Carrier_Record".get_carrier_ulds(text);
revoke all on function "Basic_Carrier_Record".get_carrier_ulds(text,text,text) from public,anon;grant execute on function "Basic_Carrier_Record".get_carrier_ulds(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_carrier_ulds(text,text,text,text,jsonb) from public,anon;grant execute on function "Basic_Carrier_Record".save_carrier_ulds(text,text,text,text,jsonb) to authenticated;
revoke all on function "Basic_Carrier_Record".save_carrier_uld_applicability(text,text,text,text,boolean) from public,anon;grant execute on function "Basic_Carrier_Record".save_carrier_uld_applicability(text,text,text,text,boolean) to authenticated;
notify pgrst,'reload schema';commit;
