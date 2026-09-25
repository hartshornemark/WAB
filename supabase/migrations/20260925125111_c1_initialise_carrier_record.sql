begin;
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".save_aircraft_c1(p_iata text, p_type_code text, p_subtype text, p_revision text, p_aircraft_name text, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
-- Aircraft setup can precede B1 (the A5 workflow needs an aircraft first).
-- Initialise only the missing carrier parent; never overwrite saved B1 choices.
insert into "Basic_Carrier_Record"."Basic_Carrier_Data"("Carrier_IATA","Carrier_Name","Carrier_ICAO")
select "Carrier_IATA","Carrier_Name","Carrier_ICAO" from "Basic_Carrier_Record"."MASTER_Carrier_Contact"
where "Carrier_IATA"=p_iata
on conflict ("Carrier_IATA") do nothing;
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
end $function$
;
commit;
