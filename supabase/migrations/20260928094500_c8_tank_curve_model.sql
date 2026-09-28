begin;

update "Basic_Carrier_Record"."Aircraft_Fuel_Loading_METHODS" m
set "Tanks"=coalesce((
 select jsonb_agg(
  (tank - 'specificGravity' - 'points')
  || jsonb_build_object(
   'sourceSpecificGravity',coalesce(tank->'sourceSpecificGravity',tank->'specificGravity','null'::jsonb),
   'points',case when jsonb_typeof(tank->'points')='array' and not exists (select 1 from jsonb_array_elements(tank->'points') p where not (p ? 'balanceArm')) then tank->'points' else '[]'::jsonb end
  )
 ) from jsonb_array_elements(m."Tanks") tank
),'[]'::jsonb);

create or replace function "Basic_Carrier_Record".get_aircraft_c8(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');aircraft "Basic_Carrier_Record"."Basic_Aircraft_Data"%rowtype;units "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"%rowtype;methods "Basic_Carrier_Record"."Aircraft_Fuel_Loading_METHODS"%rowtype;values_data jsonb;payload jsonb;tanks_data jsonb;schedules_data jsonb;by_tank boolean;by_schedule boolean;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select * into aircraft from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if aircraft."Carrier_IATA" is null then raise exception 'Aircraft not found' using errcode='23503';end if;
 select * into units from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if units."Carrier_IATA" is null then raise exception 'Complete C1 first' using errcode='23503';end if;
 select * into methods from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_METHODS" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if methods."Carrier_IATA" is null then
  by_tank:=aircraft."Non_Standard_Fuel_Loading_Enabled";by_schedule:=false;schedules_data:='[]'::jsonb;
  tanks_data:=coalesce((select jsonb_agg(jsonb_build_object('tankName',"Tank_Name",'tankShortCode',"Tank_Name_Short_Code",'sourceSpecificGravity',"SG",'maximumVolume',"Maximum_Volume",'indexPerUnitWeight',"Tank_Index_Per_Weight_Unit",'weights','[]'::jsonb,'points','[]'::jsonb) order by "Tank_Name") from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb);
 else
  by_tank:=methods."By_Tank";by_schedule:=methods."By_Schedule";tanks_data:=methods."Tanks";schedules_data:=methods."Schedules";
 end if;
 values_data:=jsonb_build_object(
  'standard',jsonb_build_object('enabled',aircraft."Standard_Fuel_Loading_Enabled",'rows',coalesce((select jsonb_agg(jsonb_build_object('specificGravity',"Fuel_Specific_Gravity",'fuelVolume',"Fuel_Volume",'fuelWeight',"Fuel_Weight",'hArm',"H-Arm",'indexValue',"Index_Value") order by "Fuel_Weight","Fuel_Specific_Gravity") from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb)),
  'nonStandard',jsonb_build_object('byTankEnabled',by_tank,'byScheduleEnabled',by_schedule,'tanks',tanks_data,'schedules',schedules_data),
  'taxiFuel',jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('isDefault',"Default",'airportIata',"Airport_IATA",'taxiFuel',"Taxi_Fuel") order by "Default" desc,"Airport_IATA") from "Basic_Carrier_Record"."Carrier_Taxi_Fuel" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_SubType"=st),'[]'::jsonb)));
 payload:=jsonb_build_object('typeCode',tc,'subtype',st,'weightUnit',units."Weight_Unit",'lengthUnit',units."Length_Unit",'liquidVolumeUnit',units."Liquid_Volume_Unit",'values',values_data);
 return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text));
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_c8(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;enabled boolean;rows_data jsonb;default_fuel integer;by_tank boolean;by_schedule boolean;tanks_data jsonb;schedules_data jsonb;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if p_section not in ('standard','nonStandard','taxiFuel') or p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Invalid C8 values' using errcode='22023';end if;
 if p_section in ('standard','taxiFuel') and jsonb_typeof(p_values->'rows')<>'array' then raise exception 'Invalid C8 rows' using errcode='22023';end if;
 if p_section='standard' and jsonb_typeof(p_values->'enabled')<>'boolean' then raise exception 'Invalid C8 standard values' using errcode='22023';end if;
 if p_section='nonStandard' and (jsonb_typeof(p_values->'byTankEnabled')<>'boolean' or jsonb_typeof(p_values->'byScheduleEnabled')<>'boolean' or jsonb_typeof(p_values->'tanks')<>'array' or jsonb_typeof(p_values->'schedules')<>'array') then raise exception 'Invalid C8 non-standard values' using errcode='22023';end if;
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
 if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_c8(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C8 changed' using errcode='40001';end if;
 if p_section='standard' then
  enabled:=(p_values->>'enabled')::boolean;rows_data:=p_values->'rows';
  update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Standard_Fuel_Loading_Enabled"=enabled where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if enabled then
   delete from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
   insert into "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD"("Carrier_IATA","Aircraft_Type_IATA","Fuel_Specific_Gravity","Fuel_Volume","Fuel_Weight","H-Arm","Index_Value","Aircraft_Series_Subtype")
   select p_iata,tc,x."specificGravity",x."fuelVolume",x."fuelWeight",x."hArm",x."indexValue",st from jsonb_to_recordset(rows_data) as x("specificGravity" double precision,"fuelVolume" integer,"fuelWeight" integer,"hArm" double precision,"indexValue" double precision);
  end if;
 elsif p_section='nonStandard' then
  by_tank:=(p_values->>'byTankEnabled')::boolean;by_schedule:=(p_values->>'byScheduleEnabled')::boolean;tanks_data:=p_values->'tanks';schedules_data:=p_values->'schedules';
  update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Non_Standard_Fuel_Loading_Enabled"=(by_tank or by_schedule) where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  insert into "Basic_Carrier_Record"."Aircraft_Fuel_Loading_METHODS"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","By_Tank","By_Schedule","Tanks","Schedules") values(p_iata,tc,st,by_tank,by_schedule,tanks_data,schedules_data)
  on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "By_Tank"=excluded."By_Tank","By_Schedule"=excluded."By_Schedule","Tanks"=excluded."Tanks","Schedules"=excluded."Schedules";
  delete from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if by_tank then
   insert into "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD"("Carrier_IATA","Aircraft_Type_IATA","Tank_Name","SG","Tank_BA_Centroid","Tank_Index_Per_Weight_Unit","Aircraft_Series_Subtype","Maximum_Volume","Tank_Name_Short_Code")
   select p_iata,tc,x."tankName",x."sourceSpecificGravity",null,x."indexPerUnitWeight",st,x."maximumVolume",upper(x."tankShortCode") from jsonb_to_recordset(tanks_data) as x("tankName" text,"tankShortCode" text,"sourceSpecificGravity" double precision,"maximumVolume" bigint,"indexPerUnitWeight" double precision) where x."indexPerUnitWeight" is not null and x."sourceSpecificGravity" is not null;
  end if;
 else
  rows_data:=p_values->'rows';
  delete from "Basic_Carrier_Record"."Carrier_Taxi_Fuel" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_SubType"=st;
  insert into "Basic_Carrier_Record"."Carrier_Taxi_Fuel"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType","Default","Airport_IATA","Taxi_Fuel")
  select p_iata,tc,st,x."isDefault",case when x."isDefault" then null else upper(x."airportIata") end,x."taxiFuel" from jsonb_to_recordset(rows_data) as x("isDefault" boolean,"airportIata" text,"taxiFuel" integer);
  select "Taxi_Fuel" into default_fuel from "Basic_Carrier_Record"."Carrier_Taxi_Fuel" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_SubType"=st and "Default";
  update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Taxi_Fuel"=default_fuel where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 end if;
 return "Basic_Carrier_Record".get_aircraft_c8(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_c8(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c8(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_c8(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c8(text,text,text,text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
