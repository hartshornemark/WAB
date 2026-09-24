begin;

create or replace function "Basic_Carrier_Record".assign_aircraft_manufacturer(
  p_type_code text,
  p_subtype text,
  p_manufacturer_uuid uuid
)
returns void
language plpgsql
security invoker
set search_path=''
as $$
declare
  affected integer;
begin
  if (select auth.uid()) is null or not private.has_global_permission('MASTER_DATA_EDIT') then
    raise exception 'Not authorised' using errcode='42501';
  end if;
  if not exists (
    select 1
    from "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"
    where "Manufacturer_UUID"=p_manufacturer_uuid
  ) then
    raise exception 'Manufacturer not found' using errcode='23503';
  end if;
  update "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
  set "Manufacturer_UUID"=p_manufacturer_uuid
  where "Aircraft_Type_IATA"=upper(btrim(p_type_code))
    and "Aircraft_Series_Subtype"=upper(btrim(p_subtype))
    and "Manufacturer_UUID" is null;
  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'Aircraft manufacturer is already assigned or the identity was not found' using errcode='40001';
  end if;
end;
$$;

revoke all on function "Basic_Carrier_Record".assign_aircraft_manufacturer(text,text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".assign_aircraft_manufacturer(text,text,uuid) to authenticated;

create or replace function "Basic_Carrier_Record".get_aircraft_c1(p_iata text,p_type_code text,p_subtype text)
returns jsonb language sql stable security invoker set search_path='' as $$
with access as(select ((private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')) and (select auth.uid()) is not null) view,
 (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) edit,
 (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_CREATE') or private.has_global_permission('AIRCRAFT_CONFIG_CREATE')) create_aircraft,
 private.has_global_permission('MASTER_DATA_EDIT') assign_manufacturer),
data as(select m."Aircraft_Type_IATA" type_code,m."Aircraft_Series_Subtype" subtype,m."Manufacturer_UUID" manufacturer_uuid,b."Aircraft_Type" aircraft_name,
 m."Aircraft_Type" identity_name,coalesce(mm."Manufacturer_Name",'') manufacturer_name,
 s."Carrier_IATA" settings_iata,s."Remarks" remarks,to_jsonb(b) basic_row,to_jsonb(s) settings_row,
 coalesce(s."Weight_Unit",case when u."Kilograms" then 'KG' when u."Pounds" then 'LB' else '' end) weight_unit,
 coalesce(s."Length_Unit",case when u."Centimeters" then 'CM' when u."Meters" then 'M' when u."Inches" then 'IN' when u."Feet" then 'FT' else '' end) length_unit,
 coalesce(s."Liquid_Volume_Unit",case when u."Litres" then 'L' when u."US Gallon" then 'US_GAL' else '' end) liquid_unit,
 coalesce(s."Volume_Unit",case when u."Carrier_IATA" is not null and exists(select 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" bx where bx."Carrier_IATA"=p_iata and bx."Carrier_Unit_Volume_m3") then 'M3' when u."Carrier_IATA" is not null then 'FT3' else '' end) volume_unit,
 coalesce(s."Fuel_Density_Unit",case when u."SG_KG_Litre" then 'KG_L' when u."SG_LB_Litre" then 'LB_L' when u."SG_KG_US_Gallon" then 'KG_US_GAL' when u."SG_LB_US_Gallon" then 'LB_US_GAL' else '' end) density_unit,
 coalesce(s."Moment_Unit",case when u."Moment_KG_in" then 'KG_IN' when u."Moment_LB_in" then 'LB_IN' when u."Moment_KG_cm" then 'KG_CM' when u."Moment_LB_cm" then 'LB_CM' when u."Moment_KG_m" then 'KG_M' when u."Moment_LB_m" then 'LB_M' else '' end) moment_unit
 from "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA" m join access a on (a.view or a.create_aircraft)
 left join "Basic_Carrier_Record"."Basic_Aircraft_Data" b on b."Carrier_IATA"=p_iata and b."Aircraft_Type_IATA"=m."Aircraft_Type_IATA" and b."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
 left join "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures" mm on mm."Manufacturer_UUID"=m."Manufacturer_UUID"
 left join "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" s on s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=m."Aircraft_Type_IATA" and s."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"
 left join "Basic_Carrier_Record"."Carrier_Units_of_Measure" u on u."Carrier_IATA"=p_iata
 where m."Aircraft_Type_IATA"=upper(p_type_code) and m."Aircraft_Series_Subtype"=upper(p_subtype))
select jsonb_build_object('canView',a.view,'canEdit',case when d.basic_row is null then a.create_aircraft else a.edit end,'canAssignManufacturer',a.assign_manufacturer,'exists',d.settings_iata is not null,'revision',case when d.basic_row is not null then md5(d.basic_row::text||coalesce(d.settings_row::text,'null')) else '' end,
 'typeCode',coalesce(d.type_code,''),'subtype',coalesce(d.subtype,''),'manufacturerId',d.manufacturer_uuid,'manufacturerName',coalesce(d.manufacturer_name,''),'identityName',coalesce(d.identity_name,''),'aircraftName',coalesce(btrim(d.aircraft_name),d.identity_name,''),
 'values',jsonb_build_object('weight',coalesce(d.weight_unit,''),'length',coalesce(d.length_unit,''),'liquidVolume',coalesce(d.liquid_unit,''),'volume',coalesce(d.volume_unit,''),'fuelDensity',coalesce(d.density_unit,''),'moment',coalesce(d.moment_unit,''),'remarks',coalesce(d.remarks,''))) from access a left join data d on true;
$$;

revoke all on function "Basic_Carrier_Record".get_aircraft_c1(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c1(text,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
