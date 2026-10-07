begin;

alter table "Basic_Carrier_Record"."Aircraft_Holds"
 add column "Applicable_Fuel_Configurations" text[] not null default '{}',
 add column "Fuel_Configuration_Overrides" jsonb not null default '[]'::jsonb,
 add constraint "Aircraft_Holds_Fuel_Overrides_Array" check (jsonb_typeof("Fuel_Configuration_Overrides")='array');
alter table "Basic_Carrier_Record"."Aircraft_Compartments"
 add column "Applicable_Fuel_Configurations" text[] not null default '{}',
 add column "Fuel_Configuration_Overrides" jsonb not null default '[]'::jsonb,
 add constraint "Aircraft_Compartments_Fuel_Overrides_Array" check (jsonb_typeof("Fuel_Configuration_Overrides")='array');
alter table "Basic_Carrier_Record"."Aircraft_Compartment_Areas"
 add column "Applicable_Fuel_Configurations" text[] not null default '{}',
 add column "Fuel_Configuration_Overrides" jsonb not null default '[]'::jsonb,
 add constraint "Aircraft_Compartment_Areas_Fuel_Overrides_Array" check (jsonb_typeof("Fuel_Configuration_Overrides")='array');
alter table "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays"
 add column "Applicable_Fuel_Configurations" text[] not null default '{}',
 add column "Fuel_Configuration_Overrides" jsonb not null default '[]'::jsonb,
 add constraint "Carrier_ULD_Atomic_Bays_Fuel_Overrides_Array" check (jsonb_typeof("Fuel_Configuration_Overrides")='array');
alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
 add column "Applicable_Fuel_Configurations" text[] not null default '{}',
 add column "Fuel_Configuration_Overrides" jsonb not null default '[]'::jsonb,
 add constraint "Carrier_ULD_Positions_Fuel_Overrides_Array" check (jsonb_typeof("Fuel_Configuration_Overrides")='array');

comment on column "Basic_Carrier_Record"."Aircraft_Holds"."Applicable_Fuel_Configurations" is 'Empty means applicable to every fitted fuel-system configuration.';
comment on column "Basic_Carrier_Record"."Aircraft_Holds"."Fuel_Configuration_Overrides" is 'Optional property overrides keyed by configurationCode.';

create or replace function private.fuel_configuration_codes(payload jsonb)
returns text[] language plpgsql immutable set search_path='' as $$
declare result text[];
begin
 if payload is null then return '{}'::text[];end if;
 if jsonb_typeof(payload)<>'array' then raise exception 'Fuel configuration scope must be an array' using errcode='22023';end if;
 select coalesce(array_agg(code order by code),'{}'::text[]) into result from (select distinct upper(btrim(value#>>'{}')) code from jsonb_array_elements(payload)) x;
 if exists(select 1 from unnest(result) code where code !~ '^[A-Z0-9][A-Z0-9-]{0,11}$') then raise exception 'Invalid fuel configuration scope' using errcode='22023';end if;
 return result;
end $$;

create or replace function private.fuel_configuration_overrides(payload jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb;
begin
 if payload is null then return '[]'::jsonb;end if;
 if jsonb_typeof(payload)<>'array' then raise exception 'Fuel configuration overrides must be an array' using errcode='22023';end if;
 select coalesce(jsonb_agg(value||jsonb_build_object('configurationCode',upper(btrim(value->>'configurationCode'))) order by upper(btrim(value->>'configurationCode'))),'[]'::jsonb) into result from jsonb_array_elements(payload);
 if exists(select 1 from jsonb_array_elements(result) item where jsonb_typeof(item)<>'object' or coalesce(item->>'configurationCode','') !~ '^[A-Z0-9][A-Z0-9-]{0,11}$') then raise exception 'Invalid fuel configuration override' using errcode='22023';end if;
 if (select count(*) from jsonb_array_elements(result))<>(select count(distinct item->>'configurationCode') from jsonb_array_elements(result) item) then raise exception 'Duplicate fuel configuration override' using errcode='22023';end if;
 return result;
end $$;

create or replace function private.assert_aircraft_fuel_scope(ci text,tc text,st text,codes text[],overrides jsonb)
returns void language plpgsql stable set search_path='' as $$
begin
 if exists(
  select 1 from (
   select unnest(codes) code union select item->>'configurationCode' from jsonb_array_elements(overrides) item
  ) requested
  where not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" f where f."Carrier_IATA"=ci and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st and f."Configuration_Code"=requested.code)
 ) then raise exception 'Unknown fitted fuel configuration' using errcode='23503';end if;
end $$;

revoke all on function private.fuel_configuration_codes(jsonb) from public,anon;
revoke all on function private.fuel_configuration_overrides(jsonb) from public,anon;
revoke all on function private.assert_aircraft_fuel_scope(text,text,text,text[],jsonb) from public,anon;
grant execute on function private.fuel_configuration_codes(jsonb) to authenticated,service_role;
grant execute on function private.fuel_configuration_overrides(jsonb) to authenticated,service_role;
grant execute on function private.assert_aircraft_fuel_scope(text,text,text,text[],jsonb) to authenticated,service_role;

do $migration$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_d2(text,text,text)'::regprocedure);updated:=definition;
 updated:=replace(updated,$old$'id',btrim(h."Hold_Name_ID"),'name'$old$,$new$'id',btrim(h."Hold_Name_ID"),'configurationCodes',to_jsonb(h."Applicable_Fuel_Configurations"),'configurationOverrides',h."Fuel_Configuration_Overrides",'name'$new$);
 updated:=replace(updated,$old$'id',btrim(c."Compartment_ID"),'areas'$old$,$new$'id',btrim(c."Compartment_ID"),'configurationCodes',to_jsonb(c."Applicable_Fuel_Configurations"),'configurationOverrides',c."Fuel_Configuration_Overrides",'areas'$new$);
 updated:=replace(updated,$old$'id',btrim(a."Area_ID"),'maxWeight'$old$,$new$'id',btrim(a."Area_ID"),'configurationCodes',to_jsonb(a."Applicable_Fuel_Configurations"),'configurationOverrides',a."Fuel_Configuration_Overrides",'maxWeight'$new$);
 updated:=replace(updated,$old$'rows',all_rows,'deckTypes'$old$,$new$'rows',all_rows,'fuelConfigurations',coalesce((select jsonb_agg(jsonb_build_object('code',f."Configuration_Code",'description',f."Description") order by f."ACT_Count",f."Configuration_Code") from "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" f where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st),'[]'::jsonb),'deckTypes'$new$);
 if updated=definition then raise exception 'get_aircraft_d2 definition changed';end if;execute updated;
end $migration$;

do $migration$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".save_aircraft_d2(text,text,text,text,text,jsonb)'::regprocedure);updated:=definition;
 updated:=replace(updated,$old$insert into "Basic_Carrier_Record"."Aircraft_Holds"("Carrier_IATA"$old$,$new$perform private.assert_aircraft_fuel_scope(p_iata,tc,st,private.fuel_configuration_codes(item->'configurationCodes'),private.fuel_configuration_overrides(item->'configurationOverrides'));
 insert into "Basic_Carrier_Record"."Aircraft_Holds"("Carrier_IATA"$new$);
 updated:=replace(updated,$old$"Hold_Type","Hold_Deck_Location") values(p_iata,tc,st,hold_id,hold_name,max_weight,max_volume,balance_centroid,balance_from,balance_to,index_value,hold_type_code,deck_code)$old$,$new$"Hold_Type","Hold_Deck_Location","Applicable_Fuel_Configurations","Fuel_Configuration_Overrides") values(p_iata,tc,st,hold_id,hold_name,max_weight,max_volume,balance_centroid,balance_from,balance_to,index_value,hold_type_code,deck_code,private.fuel_configuration_codes(item->'configurationCodes'),private.fuel_configuration_overrides(item->'configurationOverrides'))$new$);
 updated:=replace(updated,$old$"Hold_Deck_Location"=excluded."Hold_Deck_Location";$old$,$new$"Hold_Deck_Location"=excluded."Hold_Deck_Location","Applicable_Fuel_Configurations"=excluded."Applicable_Fuel_Configurations","Fuel_Configuration_Overrides"=excluded."Fuel_Configuration_Overrides";$new$);
 updated:=replace(updated,$old$insert into "Basic_Carrier_Record"."Aircraft_Compartments"("Carrier_IATA"$old$,$new$perform private.assert_aircraft_fuel_scope(p_iata,tc,st,private.fuel_configuration_codes(comp->'configurationCodes'),private.fuel_configuration_overrides(comp->'configurationOverrides'));
  insert into "Basic_Carrier_Record"."Aircraft_Compartments"("Carrier_IATA"$new$);
 updated:=replace(updated,$old$"Compartment_Index_Per_Weight_Unit") values(p_iata,tc,st,hold_id,compartment_id,max_weight,max_volume,balance_centroid,balance_from,balance_to,index_value)$old$,$new$"Compartment_Index_Per_Weight_Unit","Applicable_Fuel_Configurations","Fuel_Configuration_Overrides") values(p_iata,tc,st,hold_id,compartment_id,max_weight,max_volume,balance_centroid,balance_from,balance_to,index_value,private.fuel_configuration_codes(comp->'configurationCodes'),private.fuel_configuration_overrides(comp->'configurationOverrides'))$new$);
 updated:=replace(updated,$old$"Compartment_Index_Per_Weight_Unit"=excluded."Compartment_Index_Per_Weight_Unit";$old$,$new$"Compartment_Index_Per_Weight_Unit"=excluded."Compartment_Index_Per_Weight_Unit","Applicable_Fuel_Configurations"=excluded."Applicable_Fuel_Configurations","Fuel_Configuration_Overrides"=excluded."Fuel_Configuration_Overrides";$new$);
 updated:=replace(updated,$old$insert into "Basic_Carrier_Record"."Aircraft_Compartment_Areas"("Carrier_IATA"$old$,$new$perform private.assert_aircraft_fuel_scope(p_iata,tc,st,private.fuel_configuration_codes(area->'configurationCodes'),private.fuel_configuration_overrides(area->'configurationOverrides'));
   insert into "Basic_Carrier_Record"."Aircraft_Compartment_Areas"("Carrier_IATA"$new$);
 updated:=replace(updated,$old$"Area_Index_Per_Weight_Unit") values(p_iata,tc,st,hold_id,compartment_id,area_id,area_max_weight,area_max_volume,area_index_value)$old$,$new$"Area_Index_Per_Weight_Unit","Applicable_Fuel_Configurations","Fuel_Configuration_Overrides") values(p_iata,tc,st,hold_id,compartment_id,area_id,area_max_weight,area_max_volume,area_index_value,private.fuel_configuration_codes(area->'configurationCodes'),private.fuel_configuration_overrides(area->'configurationOverrides'))$new$);
 if updated=definition then raise exception 'save_aircraft_d2 definition changed';end if;execute updated;
end $migration$;

do $migration$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_d3(text,text,text)'::regprocedure);updated:=definition;
 updated:=replace(updated,$old$'id',btrim(h."Hold_Name_ID"),'compartments'$old$,$new$'id',btrim(h."Hold_Name_ID"),'configurationCodes',to_jsonb(h."Applicable_Fuel_Configurations"),'configurationOverrides',h."Fuel_Configuration_Overrides",'compartments'$new$);
 updated:=replace(updated,$old$'id',b."Atomic_Bay_ID",'compartmentId'$old$,$new$'id',b."Atomic_Bay_ID",'configurationCodes',to_jsonb(b."Applicable_Fuel_Configurations"),'configurationOverrides',b."Fuel_Configuration_Overrides",'compartmentId'$new$);
 updated:=replace(updated,$old$'rowType',p."ULD_Row_Type",'positionId'$old$,$new$'rowType',p."ULD_Row_Type",'configurationCodes',to_jsonb(p."Applicable_Fuel_Configurations"),'configurationOverrides',p."Fuel_Configuration_Overrides",'positionId'$new$);
 updated:=replace(updated,$old$'uldHolds',holds,'uldTypes'$old$,$new$'uldHolds',holds,'fuelConfigurations',coalesce((select jsonb_agg(jsonb_build_object('code',f."Configuration_Code",'description',f."Description") order by f."ACT_Count",f."Configuration_Code") from "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" f where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st),'[]'::jsonb),'uldTypes'$new$);
 if updated=definition then raise exception 'get_aircraft_d3 definition changed';end if;execute updated;
end $migration$;

do $migration$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".save_aircraft_d3_configuration(text,text,text,text,text,jsonb)'::regprocedure);updated:=definition;
 updated:=replace(updated,$old$insert into "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays"("Carrier_IATA"$old$,$new$perform private.assert_aircraft_fuel_scope(p_iata,tc,st,private.fuel_configuration_codes(item->'configurationCodes'),private.fuel_configuration_overrides(item->'configurationOverrides'));
 insert into "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays"("Carrier_IATA"$new$);
 updated:=replace(updated,$old$"Atomic_Bay_Colour") values(p_iata,tc,st,hold_id,code,bay_id,compartment_id,nullif(item->>'lateralCentroid','')::double precision,nullif(item->>'lateralFrom','')::double precision,nullif(item->>'lateralTo','')::double precision,(item->>'balanceCentroid')::double precision,nullif(item->>'balanceFrom','')::double precision,nullif(item->>'balanceTo','')::double precision,nullif(item->>'colour',''))$old$,$new$"Atomic_Bay_Colour","Applicable_Fuel_Configurations","Fuel_Configuration_Overrides") values(p_iata,tc,st,hold_id,code,bay_id,compartment_id,nullif(item->>'lateralCentroid','')::double precision,nullif(item->>'lateralFrom','')::double precision,nullif(item->>'lateralTo','')::double precision,(item->>'balanceCentroid')::double precision,nullif(item->>'balanceFrom','')::double precision,nullif(item->>'balanceTo','')::double precision,nullif(item->>'colour',''),private.fuel_configuration_codes(item->'configurationCodes'),private.fuel_configuration_overrides(item->'configurationOverrides'))$new$);
 updated:=replace(updated,$old$insert into "Basic_Carrier_Record"."Carrier_ULD_Positions"("Carrier_IATA"$old$,$new$perform private.assert_aircraft_fuel_scope(p_iata,tc,st,private.fuel_configuration_codes(item->'configurationCodes'),private.fuel_configuration_overrides(item->'configurationOverrides'));
 insert into "Basic_Carrier_Record"."Carrier_ULD_Positions"("Carrier_IATA"$new$);
 updated:=replace(updated,$old$"ULD_Position_Colour") values(p_iata,tc,st,hold_id,code,row_type,upper(btrim(item->>'positionId'))$old$,$new$"ULD_Position_Colour","Applicable_Fuel_Configurations","Fuel_Configuration_Overrides") values(p_iata,tc,st,hold_id,code,row_type,upper(btrim(item->>'positionId'))$new$);
 updated:=replace(updated,$old$nullif(item->>'indexPerWeightUnit','')::double precision,nullif(item->>'colour','')) returning "ULD_Position_UUID"$old$,$new$nullif(item->>'indexPerWeightUnit','')::double precision,nullif(item->>'colour',''),private.fuel_configuration_codes(item->'configurationCodes'),private.fuel_configuration_overrides(item->'configurationOverrides')) returning "ULD_Position_UUID"$new$);
 if updated=definition then raise exception 'save_aircraft_d3_configuration definition changed';end if;execute updated;
end $migration$;

notify pgrst,'reload schema';
commit;
