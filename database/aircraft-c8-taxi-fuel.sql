begin;

alter table "Basic_Carrier_Record"."Carrier_Taxi_Fuel"
 add constraint carrier_taxi_fuel_aircraft_fk foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
 add constraint carrier_taxi_fuel_value_positive check ("Taxi_Fuel">0),
 add constraint carrier_taxi_fuel_airport_valid check (("Default" and "Airport_IATA" is null) or (not "Default" and "Airport_IATA" is not null and "Airport_IATA" ~ '^[A-Z]{3}$'));

create unique index carrier_taxi_fuel_one_default on "Basic_Carrier_Record"."Carrier_Taxi_Fuel"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType") where "Default";
create unique index carrier_taxi_fuel_one_airport on "Basic_Carrier_Record"."Carrier_Taxi_Fuel"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType","Airport_IATA") where "Airport_IATA" is not null;
create index carrier_taxi_fuel_aircraft_fk_idx on "Basic_Carrier_Record"."Carrier_Taxi_Fuel"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType");

insert into "Basic_Carrier_Record"."Carrier_Taxi_Fuel"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType","Default","Airport_IATA","Taxi_Fuel")
select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",true,null,"Taxi_Fuel"
from "Basic_Carrier_Record"."Basic_Aircraft_Data"
where "Taxi_Fuel" is not null
on conflict do nothing;

create policy carrier_taxi_fuel_select on "Basic_Carrier_Record"."Carrier_Taxi_Fuel" for select to authenticated
 using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy carrier_taxi_fuel_insert on "Basic_Carrier_Record"."Carrier_Taxi_Fuel" for insert to authenticated
 with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy carrier_taxi_fuel_update on "Basic_Carrier_Record"."Carrier_Taxi_Fuel" for update to authenticated
 using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
 with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy carrier_taxi_fuel_delete on "Basic_Carrier_Record"."Carrier_Taxi_Fuel" for delete to authenticated
 using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Taxi_Fuel" to authenticated;

create or replace function "Basic_Carrier_Record".get_aircraft_c8(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');aircraft "Basic_Carrier_Record"."Basic_Aircraft_Data"%rowtype;units "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"%rowtype;values_data jsonb;payload jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select * into aircraft from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if aircraft."Carrier_IATA" is null then raise exception 'Aircraft not found' using errcode='23503';end if;
 select * into units from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if units."Carrier_IATA" is null then raise exception 'Complete C1 first' using errcode='23503';end if;
 values_data:=jsonb_build_object(
  'standard',jsonb_build_object('enabled',aircraft."Standard_Fuel_Loading_Enabled",'rows',coalesce((select jsonb_agg(jsonb_build_object('specificGravity',"Fuel_Specific_Gravity",'fuelVolume',"Fuel_Volume",'fuelWeight',"Fuel_Weight",'hArm',"H-Arm",'indexValue',"Index_Value") order by "Fuel_Weight","Fuel_Specific_Gravity") from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb)),
  'nonStandard',jsonb_build_object('enabled',aircraft."Non_Standard_Fuel_Loading_Enabled",'rows',coalesce((select jsonb_agg(jsonb_build_object('tankName',"Tank_Name",'tankShortCode',"Tank_Name_Short_Code",'specificGravity',"SG",'maximumVolume',"Maximum_Volume",'indexPerUnitWeight',"Tank_Index_Per_Weight_Unit",'balanceArm',"Tank_BA_Centroid") order by "Tank_Name") from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb)),
  'taxiFuel',jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('isDefault',"Default",'airportIata',"Airport_IATA",'taxiFuel',"Taxi_Fuel") order by "Default" desc,"Airport_IATA") from "Basic_Carrier_Record"."Carrier_Taxi_Fuel" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_SubType"=st),'[]'::jsonb)));
 payload:=jsonb_build_object('typeCode',tc,'subtype',st,'weightUnit',units."Weight_Unit",'lengthUnit',units."Length_Unit",'liquidVolumeUnit',units."Liquid_Volume_Unit",'values',values_data);
 return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text));
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_c8(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;enabled boolean;rows_data jsonb;default_fuel integer;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if p_section not in ('standard','nonStandard','taxiFuel') or p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'rows')<>'array' or (p_section in ('standard','nonStandard') and jsonb_typeof(p_values->'enabled')<>'boolean') then raise exception 'Invalid C8 values' using errcode='22023';end if;
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
 if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_c8(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C8 changed' using errcode='40001';end if;
 rows_data:=p_values->'rows';
 if p_section='standard' then
  enabled:=(p_values->>'enabled')::boolean;
  update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Standard_Fuel_Loading_Enabled"=enabled where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if enabled then
   delete from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
   insert into "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD"("Carrier_IATA","Aircraft_Type_IATA","Fuel_Specific_Gravity","Fuel_Volume","Fuel_Weight","H-Arm","Index_Value","Aircraft_Series_Subtype")
   select p_iata,tc,x."specificGravity",x."fuelVolume",x."fuelWeight",x."hArm",x."indexValue",st from jsonb_to_recordset(rows_data) as x("specificGravity" double precision,"fuelVolume" integer,"fuelWeight" integer,"hArm" double precision,"indexValue" double precision);
  end if;
 elsif p_section='nonStandard' then
  enabled:=(p_values->>'enabled')::boolean;
  update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Non_Standard_Fuel_Loading_Enabled"=enabled where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if enabled then
   delete from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
   insert into "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD"("Carrier_IATA","Aircraft_Type_IATA","Tank_Name","SG","Tank_BA_Centroid","Tank_Index_Per_Weight_Unit","Aircraft_Series_Subtype","Maximum_Volume","Tank_Name_Short_Code")
   select p_iata,tc,x."tankName",x."specificGravity",x."balanceArm",x."indexPerUnitWeight",st,x."maximumVolume",upper(x."tankShortCode") from jsonb_to_recordset(rows_data) as x("tankName" text,"tankShortCode" text,"specificGravity" double precision,"maximumVolume" bigint,"indexPerUnitWeight" double precision,"balanceArm" double precision);
  end if;
 else
  delete from "Basic_Carrier_Record"."Carrier_Taxi_Fuel" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_SubType"=st;
  insert into "Basic_Carrier_Record"."Carrier_Taxi_Fuel"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType","Default","Airport_IATA","Taxi_Fuel")
  select p_iata,tc,st,x."isDefault",case when x."isDefault" then null else upper(x."airportIata") end,x."taxiFuel" from jsonb_to_recordset(rows_data) as x("isDefault" boolean,"airportIata" text,"taxiFuel" integer);
  select "Taxi_Fuel" into default_fuel from "Basic_Carrier_Record"."Carrier_Taxi_Fuel" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_SubType"=st and "Default";
  update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Taxi_Fuel"=default_fuel where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 end if;
 return "Basic_Carrier_Record".get_aircraft_c8(p_iata,tc,st);
end $$;

notify pgrst,'reload schema';
commit;
