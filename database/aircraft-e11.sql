begin;

alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  add column if not exists "Start_Weight_Principle" character varying(20);
alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  drop constraint if exists "Basic_Aircraft_Data_Start_Weight_Principle_check";
alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  add constraint "Basic_Aircraft_Data_Start_Weight_Principle_check"
  check ("Start_Weight_Principle" is null or "Start_Weight_Principle" in ('BASIC_WEIGHT','DRY_OPERATING_WEIGHT'));

update "Basic_Carrier_Record"."Basic_Aircraft_Data" a
set "Start_Weight_Principle"=case
  when b."Carrier_Basic_Weight" then 'BASIC_WEIGHT'
  when b."Carrier_Dry_Operating_Weight" then 'DRY_OPERATING_WEIGHT'
  else null end
from "Basic_Carrier_Record"."Basic_Carrier_Data" b
where b."Carrier_IATA"=a."Carrier_IATA" and a."Start_Weight_Principle" is null;

alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"
  add column if not exists "Basic_Weight" integer,
  add column if not exists "Basic_Index" double precision;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"
  drop constraint if exists "Carrier_Aircraft_Fleet_Basic_Weight_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"
  add constraint "Carrier_Aircraft_Fleet_Basic_Weight_check"
  check ("Basic_Weight" is null or "Basic_Weight">0);
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"
  drop constraint if exists "Carrier_Aircraft_Fleet_Basic_Index_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"
  add constraint "Carrier_Aircraft_Fleet_Basic_Index_check"
  check ("Basic_Index" is null or abs("Basic_Index")<=1000000000);

update "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions"
set "Included"=true where "DOW_Item"='Basic Weight' and not "Included";
alter table "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions"
  drop constraint if exists "Carrier_DOW_Inclusions_Basic_Weight_required";
alter table "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions"
  add constraint "Carrier_DOW_Inclusions_Basic_Weight_required"
  check ("DOW_Item"<>'Basic Weight' or "Included");

drop policy if exists e11_aircraft_config_select on "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions";
create policy e11_aircraft_config_select on "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions" for select to authenticated
using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
drop policy if exists e11_aircraft_config_insert on "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions";
create policy e11_aircraft_config_insert on "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions" for insert to authenticated
with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
drop policy if exists e11_aircraft_config_update on "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions";
create policy e11_aircraft_config_update on "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions" for update to authenticated
using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

create or replace function "Basic_Carrier_Record".get_aircraft_e11(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));principle text;items jsonb;can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');payload jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select "Start_Weight_Principle" into principle from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('item',m."DOW_Item",'included',case when m."DOW_Item"='Basic Weight' then true else coalesce(c."Included",m."Included") end,'remarks',m."Remarks") order by case m."DOW_Item" when 'Basic Weight' then 0 else 1 end,m."DOW_Item"),'[]'::jsonb) into items
 from "Basic_Carrier_Record"."MASTER_Dry_Operating_Weight_Inclusions" m left join "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions" c on c."Carrier_IATA"=p_iata and c."DOW_Item"=m."DOW_Item";
 payload:=jsonb_build_object('principle',principle,'inclusions',items);
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text),'typeCode',tc,'subtype',st,'principle',principle,'inclusions',items);
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_e11(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_e11(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_e11(p_iata text,p_type_code text,p_subtype text,p_revision text,p_value jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;principle text;items jsonb:=p_value->'inclusions';item jsonb;item_name text;included boolean;expected_count integer;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e11(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 principle:=current_data->>'principle';
 if principle not in ('BASIC_WEIGHT','DRY_OPERATING_WEIGHT') then raise exception 'Invalid starting weight principle' using errcode='23514';end if;
 if jsonb_typeof(items)<>'array' then raise exception 'Inclusions must be an array' using errcode='22023';end if;
 select count(*) into expected_count from "Basic_Carrier_Record"."MASTER_Dry_Operating_Weight_Inclusions";
 if jsonb_array_length(items)<>expected_count then raise exception 'Complete inclusion list required' using errcode='22023';end if;
 if (select count(distinct value->>'item') from jsonb_array_elements(items))<>expected_count then raise exception 'Duplicate or missing inclusion' using errcode='23514';end if;
 update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Start_Weight_Principle"=principle where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
 for item in select value from jsonb_array_elements(items) loop
  item_name:=btrim(item->>'item');included:=case when item_name='Basic Weight' then true else coalesce((item->>'included')::boolean,false) end;
  if not exists(select 1 from "Basic_Carrier_Record"."MASTER_Dry_Operating_Weight_Inclusions" where "DOW_Item"=item_name) then raise exception 'Unknown inclusion' using errcode='23503';end if;
  insert into "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions"("Carrier_IATA","DOW_Item","Included") values(p_iata,item_name,included)
  on conflict("Carrier_IATA","DOW_Item") do update set "Included"=excluded."Included";
 end loop;
 return "Basic_Carrier_Record".get_aircraft_e11(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_e11(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_e11(text,text,text,text,jsonb) to authenticated;

commit;
