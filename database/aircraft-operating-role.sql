begin;

alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  add column if not exists "Aircraft_Operating_Role" varchar(9) not null default 'PASSENGER';

alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  drop constraint if exists "Basic_Aircraft_Data_Operating_Role_check";
alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  add constraint "Basic_Aircraft_Data_Operating_Role_check"
  check ("Aircraft_Operating_Role" in ('PASSENGER','FREIGHTER','COMBI'));

create or replace function "Basic_Carrier_Record".get_carrier_aircraft(p_iata text)
returns jsonb language sql stable security invoker set search_path='' as $$
with access as (select ((private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')) and (select auth.uid()) is not null) as view,
 (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_CREATE') or private.has_global_permission('AIRCRAFT_CONFIG_CREATE')) as create_aircraft,
 private.has_global_permission('MASTER_DATA_CREATE') as create_identity),
rows as (select coalesce(jsonb_agg(jsonb_build_object('typeCode',b."Aircraft_Type_IATA",'subtype',b."Aircraft_Series_Subtype",'aircraftName',btrim(b."Aircraft_Type"),'identityName',m."Aircraft_Type",'manufacturerName',coalesce(mm."Manufacturer_Name",''),'operatingRole',coalesce(b."Aircraft_Operating_Role",'PASSENGER'),'variantCodes',coalesce((select jsonb_agg(v."Carrier_Variant_Code" order by v."Carrier_Variant_Code") from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v where v."Carrier_IATA"=b."Carrier_IATA" and v."Aircraft_Type_IATA"=b."Aircraft_Type_IATA" and v."Aircraft_Series_Subtype"=b."Aircraft_Series_Subtype"),jsonb_build_array(b."Aircraft_Series_Subtype")),'configured',s."Carrier_IATA" is not null) order by b."Aircraft_Type_IATA",b."Aircraft_Series_Subtype"),'[]'::jsonb) list
 from "Basic_Carrier_Record"."Basic_Aircraft_Data" b join access a on a.view
 join "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA" m using("Aircraft_Type_IATA","Aircraft_Series_Subtype")
 left join "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures" mm on mm."Manufacturer_UUID"=m."Manufacturer_UUID"
 left join "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" s using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") where b."Carrier_IATA"=p_iata)
select jsonb_build_object('canView',a.view,'canCreateAircraft',a.create_aircraft,'canCreateIdentity',a.create_identity,'rows',r.list) from access a cross join rows r;
$$;

create or replace function "Basic_Carrier_Record".get_aircraft_c1(p_iata text,p_type_code text,p_subtype text)
returns jsonb language sql stable security invoker set search_path='' as $$
with access as(select ((private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')) and (select auth.uid()) is not null) view,
 (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) edit,
 (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_CREATE') or private.has_global_permission('AIRCRAFT_CONFIG_CREATE')) create_aircraft,
 private.has_global_permission('MASTER_DATA_EDIT') assign_manufacturer),
data as(select m."Aircraft_Type_IATA" type_code,m."Aircraft_Series_Subtype" subtype,m."Manufacturer_UUID" manufacturer_uuid,b."Aircraft_Type" aircraft_name,coalesce(b."Aircraft_Operating_Role",'PASSENGER') operating_role,
 m."Aircraft_Type" identity_name,coalesce(mm."Manufacturer_Name",'') manufacturer_name,
 s."Carrier_IATA" settings_iata,s."Remarks" remarks,to_jsonb(b) basic_row,to_jsonb(s) settings_row,
 coalesce((select jsonb_agg(v."Carrier_Variant_Code" order by v."Carrier_Variant_Code") from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=m."Aircraft_Type_IATA" and v."Aircraft_Series_Subtype"=m."Aircraft_Series_Subtype"),jsonb_build_array(m."Aircraft_Series_Subtype")) variants,
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
select jsonb_build_object('canView',a.view,'canEdit',case when d.basic_row is null then a.create_aircraft else a.edit end,'canAssignManufacturer',a.assign_manufacturer,'exists',d.settings_iata is not null,'revision',case when d.basic_row is not null then md5(d.basic_row::text||coalesce(d.settings_row::text,'null')||d.variants::text) else '' end,
 'typeCode',coalesce(d.type_code,''),'subtype',coalesce(d.subtype,''),'manufacturerId',d.manufacturer_uuid,'manufacturerName',coalesce(d.manufacturer_name,''),'identityName',coalesce(d.identity_name,''),'aircraftName',coalesce(btrim(d.aircraft_name),d.identity_name,''),'variantCodes',coalesce(d.variants,'[]'::jsonb),'operatingRole',coalesce(d.operating_role,'PASSENGER'),
 'values',jsonb_build_object('weight',coalesce(d.weight_unit,''),'length',coalesce(d.length_unit,''),'liquidVolume',coalesce(d.liquid_unit,''),'volume',coalesce(d.volume_unit,''),'fuelDensity',coalesce(d.density_unit,''),'moment',coalesce(d.moment_unit,''),'remarks',coalesce(d.remarks,''))) from access a left join data d on true;
$$;

create or replace function "Basic_Carrier_Record".save_aircraft_c1(p_iata text,p_type_code text,p_subtype text,p_revision text,p_aircraft_name text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));nm text:=btrim(p_aircraft_name);cur jsonb;exists_before boolean;variants text[];variant text;
begin
select exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) into exists_before;
if exists_before then
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
 cur:="Basic_Carrier_Record".get_aircraft_c1(p_iata,tc,st);if p_revision is distinct from cur->>'revision' then raise exception 'Aircraft C1 changed' using errcode='40001';end if;
else
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_CREATE') or private.has_global_permission('AIRCRAFT_CONFIG_CREATE')) then raise exception 'Not authorised' using errcode='42501';end if;
end if;
if not exists(select 1 from "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA" where "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft identity not found' using errcode='23503';end if;
if char_length(nm) not between 1 and 64 or p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'variantCodes')<>'array' or p_values->>'operatingRole' not in ('PASSENGER','FREIGHTER','COMBI') or p_values->>'weight' not in ('KG','LB') or p_values->>'length' not in ('CM','M','IN','FT') or p_values->>'liquidVolume' not in ('L','US_GAL') or p_values->>'volume' not in ('M3','FT3') or p_values->>'fuelDensity' not in ('KG_L','LB_L','KG_US_GAL','LB_US_GAL') or p_values->>'moment' not in ('KG_IN','LB_IN','KG_CM','LB_CM','KG_M','LB_M') or char_length(coalesce(p_values->>'remarks',''))>2000 then raise exception 'Invalid C1 values' using errcode='22023';end if;
select array_agg(distinct upper(btrim(value)) order by upper(btrim(value))) into variants from jsonb_array_elements_text(p_values->'variantCodes');
if variants is null or cardinality(variants)>20 or not st=any(variants) or exists(select 1 from unnest(variants) x where x !~ '^[A-Z0-9]{1,4}$') then raise exception 'Invalid Carrier Variants' using errcode='23514';end if;
if exists_before then update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Aircraft_Type"=nm,"Aircraft_Operating_Role"=p_values->>'operatingRole' where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
else insert into "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Type","Aircraft_Operating_Role") values(p_iata,tc,st,nm,p_values->>'operatingRole');end if;
insert into "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Unit","Length_Unit","Liquid_Volume_Unit","Volume_Unit","Fuel_Density_Unit","Moment_Unit","Remarks","Updated_At")
values(p_iata,tc,st,p_values->>'weight',p_values->>'length',p_values->>'liquidVolume',p_values->>'volume',p_values->>'fuelDensity',p_values->>'moment',nullif(btrim(coalesce(p_values->>'remarks','')),''),now())
on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "Weight_Unit"=excluded."Weight_Unit","Length_Unit"=excluded."Length_Unit","Liquid_Volume_Unit"=excluded."Liquid_Volume_Unit","Volume_Unit"=excluded."Volume_Unit","Fuel_Density_Unit"=excluded."Fuel_Density_Unit","Moment_Unit"=excluded."Moment_Unit","Remarks"=excluded."Remarks","Updated_At"=now();
foreach variant in array variants loop
 insert into "Basic_Carrier_Record"."Carrier_Aircraft_Variants"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code","Updated_At") values(p_iata,tc,st,variant,now()) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code") do update set "Updated_At"=now();
end loop;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v join "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code") where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st and not v."Carrier_Variant_Code"=any(variants)) then raise exception 'Carrier Variant is assigned to an aircraft registration' using errcode='23503';end if;
delete from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and not "Carrier_Variant_Code"=any(variants);
return "Basic_Carrier_Record".get_aircraft_c1(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_carrier_aircraft(text) from public,anon;
revoke all on function "Basic_Carrier_Record".get_aircraft_c1(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_c1(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_aircraft(text) to authenticated;
grant execute on function "Basic_Carrier_Record".get_aircraft_c1(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_c1(text,text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
