begin;

create table "Basic_Carrier_Record"."Carrier_Aircraft_Variants" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Carrier_Variant_Code" varchar(4) not null,
  "Updated_At" timestamptz not null default now(),
  primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code"),
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data" ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update cascade on delete cascade,
  constraint "Carrier_Aircraft_Variants_Code_check" check ("Carrier_Variant_Code" ~ '^[A-Z0-9]{1,4}$')
);

alter table "Basic_Carrier_Record"."Carrier_Aircraft_Variants" enable row level security;
revoke all on table "Basic_Carrier_Record"."Carrier_Aircraft_Variants" from public,anon,authenticated;
grant select,insert,update,delete on table "Basic_Carrier_Record"."Carrier_Aircraft_Variants" to authenticated;
create policy carrier_aircraft_variants_select on "Basic_Carrier_Record"."Carrier_Aircraft_Variants" for select to authenticated
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy carrier_aircraft_variants_insert on "Basic_Carrier_Record"."Carrier_Aircraft_Variants" for insert to authenticated
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_CREATE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_CREATE')));
create policy carrier_aircraft_variants_update on "Basic_Carrier_Record"."Carrier_Aircraft_Variants" for update to authenticated
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy carrier_aircraft_variants_delete on "Basic_Carrier_Record"."Carrier_Aircraft_Variants" for delete to authenticated
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

insert into "Basic_Carrier_Record"."Carrier_Aircraft_Variants"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code")
select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Series_Subtype"
from "Basic_Carrier_Record"."Basic_Aircraft_Data"
on conflict do nothing;

alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add column "Carrier_Variant_Code" varchar(4);
update "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" set "Carrier_Variant_Code"="Aircraft_Series_Subtype";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" alter column "Carrier_Variant_Code" set not null;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_Variant_Code_check" check("Carrier_Variant_Code" ~ '^[A-Z0-9]{1,4}$');
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_Variant_FK"
  foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code")
  references "Basic_Carrier_Record"."Carrier_Aircraft_Variants"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code")
  on update cascade on delete restrict;
create index carrier_aircraft_fleet_variant_idx on "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code");

create or replace function "Basic_Carrier_Record".get_carrier_aircraft(p_iata text)
returns jsonb language sql stable security invoker set search_path='' as $$
with access as (select ((private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')) and (select auth.uid()) is not null) as view,
 (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_CREATE') or private.has_global_permission('AIRCRAFT_CONFIG_CREATE')) as create_aircraft,
 private.has_global_permission('MASTER_DATA_CREATE') as create_identity),
rows as (select coalesce(jsonb_agg(jsonb_build_object('typeCode',b."Aircraft_Type_IATA",'subtype',b."Aircraft_Series_Subtype",'aircraftName',btrim(b."Aircraft_Type"),'identityName',m."Aircraft_Type",'manufacturerName',coalesce(mm."Manufacturer_Name",''),'variantCodes',coalesce((select jsonb_agg(v."Carrier_Variant_Code" order by v."Carrier_Variant_Code") from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v where v."Carrier_IATA"=b."Carrier_IATA" and v."Aircraft_Type_IATA"=b."Aircraft_Type_IATA" and v."Aircraft_Series_Subtype"=b."Aircraft_Series_Subtype"),jsonb_build_array(b."Aircraft_Series_Subtype")),'configured',s."Carrier_IATA" is not null) order by b."Aircraft_Type_IATA",b."Aircraft_Series_Subtype"),'[]'::jsonb) list
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
data as(select m."Aircraft_Type_IATA" type_code,m."Aircraft_Series_Subtype" subtype,m."Manufacturer_UUID" manufacturer_uuid,b."Aircraft_Type" aircraft_name,
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
 'typeCode',coalesce(d.type_code,''),'subtype',coalesce(d.subtype,''),'manufacturerId',d.manufacturer_uuid,'manufacturerName',coalesce(d.manufacturer_name,''),'identityName',coalesce(d.identity_name,''),'aircraftName',coalesce(btrim(d.aircraft_name),d.identity_name,''),'variantCodes',coalesce(d.variants,'[]'::jsonb),
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
if char_length(nm) not between 1 and 64 or p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'variantCodes')<>'array' or p_values->>'weight' not in ('KG','LB') or p_values->>'length' not in ('CM','M','IN','FT') or p_values->>'liquidVolume' not in ('L','US_GAL') or p_values->>'volume' not in ('M3','FT3') or p_values->>'fuelDensity' not in ('KG_L','LB_L','KG_US_GAL','LB_US_GAL') or p_values->>'moment' not in ('KG_IN','LB_IN','KG_CM','LB_CM','KG_M','LB_M') or char_length(coalesce(p_values->>'remarks',''))>2000 then raise exception 'Invalid C1 values' using errcode='22023';end if;
select array_agg(distinct upper(btrim(value)) order by upper(btrim(value))) into variants from jsonb_array_elements_text(p_values->'variantCodes');
if variants is null or cardinality(variants)>20 or not st=any(variants) or exists(select 1 from unnest(variants) x where x !~ '^[A-Z0-9]{1,4}$') then raise exception 'Invalid Carrier Variants' using errcode='23514';end if;
if exists_before then update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Aircraft_Type"=nm where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
else insert into "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Type") values(p_iata,tc,st,nm);end if;
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

create or replace function "Basic_Carrier_Record".get_aircraft_e12(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));p text;sfw integer;sfi double precision;rows jsonb;variants jsonb;can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');payload jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select "Start_Weight_Principle","Standard_Fleet_Weight","Standard_Fleet_Index" into p,sfw,sfi from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if not found or p is null then raise exception 'Complete E1.1 first' using errcode='23503';end if;
 select coalesce(jsonb_agg("Carrier_Variant_Code" order by "Carrier_Variant_Code"),'[]'::jsonb) into variants from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('fleetRowId',"Fleet_Row_ID",'registration',btrim("Aircraft_Registration"),'variantCode',"Carrier_Variant_Code",'weight',case when p='BASIC_WEIGHT' then "Basic_Weight" else "Dry_Operating_Weight" end,'index',case when p='BASIC_WEIGHT' then "Basic_Index" else "Dry_Operating_Index" end) order by btrim("Aircraft_Registration")),'[]'::jsonb) into rows from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference";
 payload:=jsonb_build_object('principle',p,'standardFleetWeight',sfw,'standardFleetIndex',sfi,'variantOptions',variants,'registrations',rows);
 return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text),'typeCode',tc,'subtype',st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_e12_registrations(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;p text;a text;fw integer;fi double precision;item jsonb;reg text;variant text;w integer;i double precision;regs text[]:='{}';
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;if jsonb_typeof(p_rows)<>'array' then raise exception 'Rows required' using errcode='22023';end if;p:=current_data->>'principle';
 select "Weight_Recording_Approach","Standard_Fleet_Weight","Standard_Fleet_Index" into a,fw,fi from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 for item in select value from jsonb_array_elements(p_rows) loop
  reg:=upper(btrim(item->>'registration'));variant:=upper(btrim(item->>'variantCode'));w:=nullif(item->>'weight','')::integer;i:=nullif(item->>'index','')::double precision;
  if reg !~ '^[A-Z0-9][A-Z0-9-]{0,9}$' or not exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st and v."Carrier_Variant_Code"=variant) or (w is not null and w<=0) or (i is not null and abs(i)>1000000000) then raise exception 'Invalid registration row' using errcode='23514';end if;regs:=array_append(regs,reg);
  update "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" set "Carrier_Variant_Code"=variant,"Dry_Operating_Weight"=case when p='DRY_OPERATING_WEIGHT' then w else null end,"Dry_Operating_Index"=case when p='DRY_OPERATING_WEIGHT' then i else null end,"Basic_Weight"=case when p='BASIC_WEIGHT' then w else null end,"Basic_Index"=case when p='BASIC_WEIGHT' then i else null end,"Fleet_Weight_Adjustment"=case when a='FLEET_WEIGHTS' and w is not null and fw is not null then w-fw else "Fleet_Weight_Adjustment" end,"Fleet_Index_Adjustment"=case when a='FLEET_WEIGHTS' and i is not null and fi is not null then i-fi else "Fleet_Index_Adjustment" end where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference" and btrim("Aircraft_Registration")=reg;
  if not found then insert into "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Aircraft_Registration","Carrier_IATA","Aircraft_Type_IATA","Crew_Code_ID","Pantry_Code_ID","Dry_Operating_Weight","Dry_Operating_Index","Aircraft_Series_Subtype","Carrier_Variant_Code","Basic_Weight","Basic_Index","E1_2_Registration_Reference","Fleet_Weight_Adjustment","Fleet_Index_Adjustment") values(reg,p_iata,tc,null,null,case when p='DRY_OPERATING_WEIGHT' then w else null end,case when p='DRY_OPERATING_WEIGHT' then i else null end,st,variant,case when p='BASIC_WEIGHT' then w else null end,case when p='BASIC_WEIGHT' then i else null end,true,case when a='FLEET_WEIGHTS' and w is not null and fw is not null then w-fw else null end,case when a='FLEET_WEIGHTS' and i is not null and fi is not null then i-fi else null end);end if;
 end loop;
 delete from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference" and not (btrim("Aircraft_Registration")=any(regs));
 return "Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".get_aircraft_e5(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));p text;a text;fw integer;fi double precision;rows jsonb;variants jsonb;configs jsonb;pantry jsonb;crew jsonb;can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');payload jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select "Start_Weight_Principle","Weight_Recording_Approach","Standard_Fleet_Weight","Standard_Fleet_Index" into p,a,fw,fi from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if not found or p is null then raise exception 'Complete E1.1 first' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('code',v."Carrier_Variant_Code",'label',tc||'-'||v."Carrier_Variant_Code") order by v."Carrier_Variant_Code"),'[]'::jsonb) into variants from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('fleetRowId',f."Fleet_Row_ID",'registration',btrim(f."Aircraft_Registration"),'variantCode',f."Carrier_Variant_Code",'weight',case when a='FLEET_WEIGHTS' then f."Fleet_Weight_Adjustment" when p='BASIC_WEIGHT' then f."Basic_Weight" else f."Dry_Operating_Weight" end,'index',case when a='FLEET_WEIGHTS' then f."Fleet_Index_Adjustment" when p='BASIC_WEIGHT' then f."Basic_Index" else f."Dry_Operating_Index" end,'actualWeight',case when p='BASIC_WEIGHT' then f."Basic_Weight" else f."Dry_Operating_Weight" end,'actualIndex',case when p='BASIC_WEIGHT' then f."Basic_Index" else f."Dry_Operating_Index" end,'macPercent',f."MAC_Percent",'balanceArm',f."Balance_Arm",'weightConfigurationCode',nullif(btrim(f."Weight_Configuration_Code"),''),'pantryCode',nullif(btrim(f."Pantry_Code_ID"),''),'crewCode',nullif(btrim(f."Crew_Code_ID"),''),'remarks',nullif(btrim(f."Remarks"),'')) order by btrim(f."Aircraft_Registration")),'[]'::jsonb) into rows from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st and f."E1_2_Registration_Reference";
 select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Weight_Configuration_Code"),'label',btrim(x."Weight_Configuration_Code")) order by btrim(x."Weight_Configuration_Code")),'[]') into configs from "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Pantry_Code_ID"),'label',coalesce(nullif(btrim(x."Pantry_Galley_Locations"),''),btrim(x."Pantry_Code_ID"))) order by btrim(x."Pantry_Code_ID")),'[]') into pantry from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Crew_Code_ID"),'label',coalesce(nullif(btrim(x."Crew_Definition_Description"),''),btrim(x."Crew_Code_ID"))) order by btrim(x."Crew_Code_ID")),'[]') into crew from "Basic_Carrier_Record"."Aircraft_Crew_Code_Definitions" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
 payload:=jsonb_build_object('principle',p,'approach',a,'fleetWeight',fw,'fleetIndex',fi,'rows',rows,'variantOptions',variants,'configurationOptions',configs,'pantryOptions',pantry,'crewOptions',crew);
 return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text),'typeCode',tc,'subtype',st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_e5_rows(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;p text;a text;fw integer;fi double precision;item jsonb;reg text;variant text;w integer;i double precision;aw integer;ai double precision;mac double precision;arm double precision;wc text;pc text;cc text;rem text;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e5(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023';end if;
 p:=current_data->>'principle';a:=current_data->>'approach';fw:=nullif(current_data->>'fleetWeight','')::integer;fi:=nullif(current_data->>'fleetIndex','')::double precision;if a is null then raise exception 'Select approach' using errcode='23514';end if;if a='FLEET_WEIGHTS' and (fw is null or fi is null) then raise exception 'Complete fleet values' using errcode='23514';end if;
 delete from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference";
 for item in select value from jsonb_array_elements(p_rows) loop
  reg:=upper(btrim(item->>'registration'));variant:=upper(btrim(item->>'variantCode'));w:=nullif(item->>'weight','')::integer;i:=nullif(item->>'index','')::double precision;mac:=nullif(item->>'macPercent','')::double precision;arm:=nullif(item->>'balanceArm','')::double precision;wc:=nullif(upper(btrim(item->>'weightConfigurationCode')),'');pc:=case when a='FLEET_WEIGHTS' then nullif(upper(btrim(item->>'pantryCode')),'') else null end;cc:=case when a='FLEET_WEIGHTS' then nullif(upper(btrim(item->>'crewCode')),'') else null end;rem:=nullif(btrim(item->>'remarks'),'');
  if reg !~ '^[A-Z0-9][A-Z0-9-]{0,9}$' or not exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st and v."Carrier_Variant_Code"=variant) or w is null or i is null or (a='INDIVIDUAL_AIRCRAFT_WEIGHTS' and w<=0) or abs(i)>1000000000 or (mac is not null and abs(mac)>1000000000) or (arm is not null and abs(arm)>1000000000) or length(coalesce(rem,''))>500 then raise exception 'Invalid E5 row' using errcode='23514';end if;
  aw:=case when a='FLEET_WEIGHTS' then fw+w else w end;ai:=case when a='FLEET_WEIGHTS' then fi+i else i end;if aw<=0 then raise exception 'Invalid actual weight' using errcode='23514';end if;
  insert into "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Aircraft_Registration","Carrier_IATA","Aircraft_Type_IATA","Crew_Code_ID","Pantry_Code_ID","Dry_Operating_Weight","Dry_Operating_Index","Aircraft_Series_Subtype","Carrier_Variant_Code","Basic_Weight","Basic_Index","E1_2_Registration_Reference","Fleet_Weight_Adjustment","Fleet_Index_Adjustment","MAC_Percent","Balance_Arm","Weight_Configuration_Code","Remarks") values(reg,p_iata,tc,cc,pc,case when p='DRY_OPERATING_WEIGHT' then aw else null end,case when p='DRY_OPERATING_WEIGHT' then ai else null end,st,variant,case when p='BASIC_WEIGHT' then aw else null end,case when p='BASIC_WEIGHT' then ai else null end,true,case when a='FLEET_WEIGHTS' then w else null end,case when a='FLEET_WEIGHTS' then i else null end,mac,arm,wc,rem);
 end loop;
 return "Basic_Carrier_Record".get_aircraft_e5(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_carrier_aircraft(text) from public,anon;
revoke all on function "Basic_Carrier_Record".get_aircraft_c1(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_c1(text,text,text,text,text,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".get_aircraft_e12(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_e12_registrations(text,text,text,text,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".get_aircraft_e5(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_e5_rows(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_aircraft(text) to authenticated;
grant execute on function "Basic_Carrier_Record".get_aircraft_c1(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_c1(text,text,text,text,text,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".get_aircraft_e12(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_e12_registrations(text,text,text,text,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".get_aircraft_e5(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_e5_rows(text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
