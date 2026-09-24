begin;

-- C1 is the first step in staged aircraft setup. Later-sheet weights must not
-- be required before an aircraft can be adopted by a carrier.
alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  alter column "MZFW" drop not null,
  alter column "MLAW" drop not null,
  alter column "MTOW" drop not null,
  alter column "MRW" drop not null,
  alter column "Taxi_Fuel" drop not null;

-- Existing aircraft RLS policies must recognise the same global permissions
-- used by Solution Administrators as well as carrier-scoped permissions.
alter policy "perm_aircraft_select" on "Basic_Carrier_Record"."Basic_Aircraft_Data"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
alter policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Basic_Aircraft_Data"
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_CREATE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_CREATE')));
alter policy "perm_aircraft_update" on "Basic_Carrier_Record"."Basic_Aircraft_Data"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Basic_Aircraft_Data"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_DELETE')));

alter table "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
  add constraint "MASTER_Aircraft_Type_IATA_Code_Alphanumeric"
    check ("Aircraft_Type_IATA" ~ '^[A-Z0-9]{3}$'),
  add constraint "MASTER_Aircraft_Type_IATA_Subtype_Alphanumeric"
    check ("Aircraft_Series_Subtype" ~ '^[A-Z0-9]{1,4}$'),
  add constraint "MASTER_Aircraft_Type_IATA_Name_Not_Blank"
    check ("Aircraft_Type" = btrim("Aircraft_Type") and char_length("Aircraft_Type") between 1 and 64);

create table "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Weight_Unit" text not null check ("Weight_Unit" in ('KG','LB')),
  "Length_Unit" text not null check ("Length_Unit" in ('CM','M','IN','FT')),
  "Liquid_Volume_Unit" text not null check ("Liquid_Volume_Unit" in ('L','US_GAL')),
  "Volume_Unit" text not null check ("Volume_Unit" in ('M3','FT3')),
  "Fuel_Density_Unit" text not null check ("Fuel_Density_Unit" in ('KG_L','LB_L','KG_US_GAL','LB_US_GAL')),
  "Moment_Unit" text not null check ("Moment_Unit" in ('KG_IN','LB_IN','KG_CM','LB_CM','KG_M','LB_M')),
  "Remarks" text null check ("Remarks" is null or ("Remarks" = btrim("Remarks") and char_length("Remarks") between 1 and 2000)),
  "Updated_At" timestamptz not null default now(),
  primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data" ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update restrict on delete cascade
);

alter table "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" enable row level security;
revoke all on table "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" from public,anon,authenticated;
grant select,insert,update,delete on table "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" to authenticated;
create policy "aircraft_c1_select" on "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"
  for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "aircraft_c1_insert" on "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"
  for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_CREATE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_CREATE')));
create policy "aircraft_c1_update" on "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"
  for update to authenticated
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_c1_delete" on "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"
  for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_DELETE')));

create function "Basic_Carrier_Record".search_aircraft_manufacturers(p_query text)
returns jsonb language sql stable security invoker set search_path='' as $$
select case when (select auth.uid()) is null or not private.has_any_permission('MASTER_DATA_VIEW') then '[]'::jsonb else
  coalesce((select jsonb_agg(jsonb_build_object('id',x."Manufacturer_UUID",'name',x."Manufacturer_Name") order by x.rank,x."Manufacturer_Name")
  from (select m.*,case when lower(m."Manufacturer_Name") like lower(btrim(p_query))||'%' then 0 else 1 end rank
        from "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures" m
        where char_length(btrim(p_query))>=2 and lower(m."Manufacturer_Name") like '%'||lower(btrim(p_query))||'%'
        order by rank,m."Manufacturer_Name" limit 10) x),'[]'::jsonb) end;
$$;
revoke all on function "Basic_Carrier_Record".search_aircraft_manufacturers(text) from public,anon;
grant execute on function "Basic_Carrier_Record".search_aircraft_manufacturers(text) to authenticated;

create function "Basic_Carrier_Record".search_aircraft_identities(p_query text)
returns jsonb language sql stable security invoker set search_path='' as $$
select case when (select auth.uid()) is null or not private.has_any_permission('MASTER_DATA_VIEW') then '[]'::jsonb else
  coalesce((select jsonb_agg(jsonb_build_object('typeCode',x."Aircraft_Type_IATA",'subtype',x."Aircraft_Series_Subtype",'identityName',x."Aircraft_Type",'manufacturerId',x."Manufacturer_UUID",'manufacturerName',coalesce(x."Manufacturer_Name",'')) order by x.rank,x."Aircraft_Type_IATA",x."Aircraft_Series_Subtype")
  from (select a.*,m."Manufacturer_Name",case when lower(a."Aircraft_Type_IATA") like lower(btrim(p_query))||'%' or lower(a."Aircraft_Type") like lower(btrim(p_query))||'%' then 0 else 1 end rank
        from "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA" a
        left join "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures" m using("Manufacturer_UUID")
        where char_length(btrim(p_query))>=2 and (lower(a."Aircraft_Type_IATA") like '%'||lower(btrim(p_query))||'%' or lower(a."Aircraft_Type") like '%'||lower(btrim(p_query))||'%' or lower(a."Aircraft_Series_Subtype") like '%'||lower(btrim(p_query))||'%' or lower(coalesce(m."Manufacturer_Name",'')) like '%'||lower(btrim(p_query))||'%')
        order by rank,a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype" limit 10) x),'[]'::jsonb) end;
$$;
revoke all on function "Basic_Carrier_Record".search_aircraft_identities(text) from public,anon;
grant execute on function "Basic_Carrier_Record".search_aircraft_identities(text) to authenticated;

create function "Basic_Carrier_Record".create_aircraft_identity(p_manufacturer_uuid uuid,p_manufacturer_name text,p_type_code text,p_subtype text,p_identity_name text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare mid uuid;tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));nm text:=btrim(p_identity_name);mn text:=btrim(p_manufacturer_name);
begin
if not private.has_global_permission('MASTER_DATA_CREATE') then raise exception 'Not authorised' using errcode='42501';end if;
if tc !~ '^[A-Z0-9]{3}$' or st !~ '^[A-Z0-9]{1,4}$' or char_length(nm) not between 1 and 64 then raise exception 'Invalid aircraft identity' using errcode='22023';end if;
if p_manufacturer_uuid is not null then select "Manufacturer_UUID" into mid from "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures" where "Manufacturer_UUID"=p_manufacturer_uuid;
else
 if char_length(mn) not between 1 and 64 or mn<>p_manufacturer_name then raise exception 'Invalid manufacturer' using errcode='22023';end if;
 select "Manufacturer_UUID" into mid from "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures" where lower("Manufacturer_Name")=lower(mn);
 if mid is null then insert into "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures"("Manufacturer_Name") values(mn) returning "Manufacturer_UUID" into mid;end if;
end if;
if mid is null then raise exception 'Manufacturer not found' using errcode='23503';end if;
insert into "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"("Aircraft_Type_IATA","Aircraft_Type","Aircraft_Series_Subtype","Manufacturer_UUID") values(tc,nm,st,mid);
return jsonb_build_object('typeCode',tc,'subtype',st,'identityName',nm,'manufacturerId',mid,'manufacturerName',(select "Manufacturer_Name" from "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures" where "Manufacturer_UUID"=mid));
end $$;
revoke all on function "Basic_Carrier_Record".create_aircraft_identity(uuid,text,text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".create_aircraft_identity(uuid,text,text,text,text) to authenticated;

create function "Basic_Carrier_Record".get_carrier_aircraft(p_iata text)
returns jsonb language sql stable security invoker set search_path='' as $$
with access as (select ((private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')) and (select auth.uid()) is not null) as view,
 (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_CREATE') or private.has_global_permission('AIRCRAFT_CONFIG_CREATE')) as create_aircraft,
 private.has_global_permission('MASTER_DATA_CREATE') as create_identity),
rows as (select coalesce(jsonb_agg(jsonb_build_object('typeCode',b."Aircraft_Type_IATA",'subtype',b."Aircraft_Series_Subtype",'aircraftName',btrim(b."Aircraft_Type"),'identityName',m."Aircraft_Type",'manufacturerName',coalesce(mm."Manufacturer_Name",''),'configured',s."Carrier_IATA" is not null) order by b."Aircraft_Type_IATA",b."Aircraft_Series_Subtype"),'[]'::jsonb) list
 from "Basic_Carrier_Record"."Basic_Aircraft_Data" b join access a on a.view
 join "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA" m using("Aircraft_Type_IATA","Aircraft_Series_Subtype")
 left join "Basic_Carrier_Record"."MASTER_Aircraft_Manufactures" mm on mm."Manufacturer_UUID"=m."Manufacturer_UUID"
 left join "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" s using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") where b."Carrier_IATA"=p_iata)
select jsonb_build_object('canView',a.view,'canCreateAircraft',a.create_aircraft,'canCreateIdentity',a.create_identity,'rows',r.list) from access a cross join rows r;
$$;
revoke all on function "Basic_Carrier_Record".get_carrier_aircraft(text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_aircraft(text) to authenticated;

create function "Basic_Carrier_Record".get_aircraft_c1(p_iata text,p_type_code text,p_subtype text)
returns jsonb language sql stable security invoker set search_path='' as $$
with access as(select ((private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')) and (select auth.uid()) is not null) view,
 (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) edit,
 (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_CREATE') or private.has_global_permission('AIRCRAFT_CONFIG_CREATE')) create_aircraft),
data as(select m."Aircraft_Type_IATA" type_code,m."Aircraft_Series_Subtype" subtype,b."Aircraft_Type" aircraft_name,
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
select jsonb_build_object('canView',a.view,'canEdit',case when d.basic_row is null then a.create_aircraft else a.edit end,'exists',d.settings_iata is not null,'revision',case when d.basic_row is not null then md5(d.basic_row::text||coalesce(d.settings_row::text,'null')) else '' end,
 'typeCode',coalesce(d.type_code,''),'subtype',coalesce(d.subtype,''),'manufacturerName',coalesce(d.manufacturer_name,''),'identityName',coalesce(d.identity_name,''),'aircraftName',coalesce(btrim(d.aircraft_name),d.identity_name,''),
 'values',jsonb_build_object('weight',coalesce(d.weight_unit,''),'length',coalesce(d.length_unit,''),'liquidVolume',coalesce(d.liquid_unit,''),'volume',coalesce(d.volume_unit,''),'fuelDensity',coalesce(d.density_unit,''),'moment',coalesce(d.moment_unit,''),'remarks',coalesce(d.remarks,''))) from access a left join data d on true;
$$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c1(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c1(text,text,text) to authenticated;

create function "Basic_Carrier_Record".save_aircraft_c1(p_iata text,p_type_code text,p_subtype text,p_revision text,p_aircraft_name text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));nm text:=btrim(p_aircraft_name);cur jsonb;exists_before boolean;
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
if char_length(nm) not between 1 and 64 or p_values is null or jsonb_typeof(p_values)<>'object' or p_values->>'weight' not in ('KG','LB') or p_values->>'length' not in ('CM','M','IN','FT') or p_values->>'liquidVolume' not in ('L','US_GAL') or p_values->>'volume' not in ('M3','FT3') or p_values->>'fuelDensity' not in ('KG_L','LB_L','KG_US_GAL','LB_US_GAL') or p_values->>'moment' not in ('KG_IN','LB_IN','KG_CM','LB_CM','KG_M','LB_M') or char_length(coalesce(p_values->>'remarks',''))>2000 then raise exception 'Invalid C1 values' using errcode='22023';end if;
if exists_before then update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Aircraft_Type"=nm where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
else insert into "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Type") values(p_iata,tc,st,nm);end if;
insert into "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Unit","Length_Unit","Liquid_Volume_Unit","Volume_Unit","Fuel_Density_Unit","Moment_Unit","Remarks","Updated_At")
values(p_iata,tc,st,p_values->>'weight',p_values->>'length',p_values->>'liquidVolume',p_values->>'volume',p_values->>'fuelDensity',p_values->>'moment',nullif(btrim(coalesce(p_values->>'remarks','')),''),now())
on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "Weight_Unit"=excluded."Weight_Unit","Length_Unit"=excluded."Length_Unit","Liquid_Volume_Unit"=excluded."Liquid_Volume_Unit","Volume_Unit"=excluded."Volume_Unit","Fuel_Density_Unit"=excluded."Fuel_Density_Unit","Moment_Unit"=excluded."Moment_Unit","Remarks"=excluded."Remarks","Updated_At"=now();
return "Basic_Carrier_Record".get_aircraft_c1(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_c1(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c1(text,text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
