begin;

alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add column if not exists "Fleet_Row_ID" uuid default gen_random_uuid();
update "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" set "Fleet_Row_ID"=gen_random_uuid() where "Fleet_Row_ID" is null;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" alter column "Fleet_Row_ID" set not null;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_pkey";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_pkey" primary key("Fleet_Row_ID");
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add column if not exists "E1_2_Registration_Reference" boolean not null default false;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" alter column "Crew_Code_ID" drop not null;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" alter column "Pantry_Code_ID" drop not null;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" alter column "Dry_Operating_Weight" drop not null;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" alter column "Dry_Operating_Index" drop not null;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" alter column "Aircraft_Registration" type character varying(10) using btrim("Aircraft_Registration");
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_Registration_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_Registration_check" check("Aircraft_Registration" ~ '^[A-Z0-9][A-Z0-9-]{0,9}$');
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_DOW_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_DOW_check" check("Dry_Operating_Weight" is null or "Dry_Operating_Weight">0);
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_DOI_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_DOI_check" check("Dry_Operating_Index" is null or abs("Dry_Operating_Index")<=1000000000);
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_reference_row_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_reference_row_check" check(not "E1_2_Registration_Reference" or ("Crew_Code_ID" is null and "Pantry_Code_ID" is null));
create unique index if not exists carrier_aircraft_fleet_detail_unique on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Aircraft_Registration","Carrier_IATA","Aircraft_Type_IATA","Crew_Code_ID","Pantry_Code_ID","Aircraft_Series_Subtype") where not "E1_2_Registration_Reference";
create unique index if not exists carrier_aircraft_fleet_e12_reference_unique on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Registration") where "E1_2_Registration_Reference";
create index if not exists carrier_aircraft_fleet_crew_fk_idx on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID");
create index if not exists carrier_aircraft_fleet_pantry_fk_idx on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Carrier_IATA","Aircraft_Type_IATA","Pantry_Code_ID","Aircraft_Series_Subtype");

insert into "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Aircraft_Registration","Carrier_IATA","Aircraft_Type_IATA","Crew_Code_ID","Pantry_Code_ID","Dry_Operating_Weight","Dry_Operating_Index","Aircraft_Series_Subtype","Basic_Weight","Basic_Index","E1_2_Registration_Reference")
select distinct on ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Registration") btrim("Aircraft_Registration"),"Carrier_IATA","Aircraft_Type_IATA",null,null,"Dry_Operating_Weight","Dry_Operating_Index","Aircraft_Series_Subtype","Basic_Weight","Basic_Index",true
from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f
where not "E1_2_Registration_Reference"
and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" r where r."Carrier_IATA"=f."Carrier_IATA" and r."Aircraft_Type_IATA"=f."Aircraft_Type_IATA" and r."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and btrim(r."Aircraft_Registration")=btrim(f."Aircraft_Registration") and r."E1_2_Registration_Reference")
order by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Registration","Dry_Operating_Weight" nulls last;

drop policy if exists e12_aircraft_config_select on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet";
create policy e12_aircraft_config_select on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" for select to authenticated using ("E1_2_Registration_Reference" and ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW'))));
drop policy if exists e12_aircraft_config_insert on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet";
create policy e12_aircraft_config_insert on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" for insert to authenticated with check ("E1_2_Registration_Reference" and ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))));
drop policy if exists e12_aircraft_config_update on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet";
create policy e12_aircraft_config_update on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" for update to authenticated using ("E1_2_Registration_Reference" and ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))) with check ("E1_2_Registration_Reference" and ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))));
drop policy if exists e12_aircraft_config_delete on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet";
create policy e12_aircraft_config_delete on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" for delete to authenticated using ("E1_2_Registration_Reference" and ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))));

create or replace function "Basic_Carrier_Record".get_aircraft_e12(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));p text;sfw integer;sfi double precision;rows jsonb;can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');payload jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select "Start_Weight_Principle","Standard_Fleet_Weight","Standard_Fleet_Index" into p,sfw,sfi from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if not found or p is null then raise exception 'Complete E1.1 first' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('fleetRowId',"Fleet_Row_ID",'registration',btrim("Aircraft_Registration"),'weight',case when p='BASIC_WEIGHT' then "Basic_Weight" else "Dry_Operating_Weight" end,'index',case when p='BASIC_WEIGHT' then "Basic_Index" else "Dry_Operating_Index" end) order by btrim("Aircraft_Registration")),'[]'::jsonb) into rows from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference";
 payload:=jsonb_build_object('principle',p,'standardFleetWeight',sfw,'standardFleetIndex',sfi,'registrations',rows);
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text),'typeCode',tc,'subtype',st,'principle',p,'standardFleetWeight',sfw,'standardFleetIndex',sfi,'registrations',rows);
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_e12(text,text,text) from public,anon;grant execute on function "Basic_Carrier_Record".get_aircraft_e12(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_e12_standard(p_iata text,p_type_code text,p_subtype text,p_revision text,p_value jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;w integer;i double precision;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 w:=nullif(p_value->>'standardFleetWeight','')::integer;i:=nullif(p_value->>'standardFleetIndex','')::double precision;if w is not null and w<=0 then raise exception 'Invalid SFW' using errcode='23514';end if;if i is not null and abs(i)>1000000000 then raise exception 'Invalid SFI' using errcode='23514';end if;
 update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Standard_Fleet_Weight"=w,"Standard_Fleet_Index"=i where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 return "Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_e12_standard(text,text,text,text,jsonb) from public,anon;grant execute on function "Basic_Carrier_Record".save_aircraft_e12_standard(text,text,text,text,jsonb) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_e12_registrations(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;p text;item jsonb;reg text;w integer;i double precision;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;if jsonb_typeof(p_rows)<>'array' then raise exception 'Rows required' using errcode='22023';end if;p:=current_data->>'principle';
 delete from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference";
 for item in select value from jsonb_array_elements(p_rows) loop
  reg:=upper(btrim(item->>'registration'));w:=nullif(item->>'weight','')::integer;i:=nullif(item->>'index','')::double precision;
  if reg !~ '^[A-Z0-9][A-Z0-9-]{0,9}$' or (w is not null and w<=0) or (i is not null and abs(i)>1000000000) then raise exception 'Invalid registration row' using errcode='23514';end if;
  insert into "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Aircraft_Registration","Carrier_IATA","Aircraft_Type_IATA","Crew_Code_ID","Pantry_Code_ID","Dry_Operating_Weight","Dry_Operating_Index","Aircraft_Series_Subtype","Basic_Weight","Basic_Index","E1_2_Registration_Reference") values(reg,p_iata,tc,null,null,case when p='DRY_OPERATING_WEIGHT' then w else null end,case when p='DRY_OPERATING_WEIGHT' then i else null end,st,case when p='BASIC_WEIGHT' then w else null end,case when p='BASIC_WEIGHT' then i else null end,true);
 end loop;
 return "Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_e12_registrations(text,text,text,text,jsonb) from public,anon;grant execute on function "Basic_Carrier_Record".save_aircraft_e12_registrations(text,text,text,text,jsonb) to authenticated;

commit;
