begin;
alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
 add column "Standard_Fuel_Loading_Enabled" boolean not null default false,
 add column "Non_Standard_Fuel_Loading_Enabled" boolean not null default false;
update "Basic_Carrier_Record"."Basic_Aircraft_Data" a set "Standard_Fuel_Loading_Enabled"=true where exists(select 1 from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" r where (r."Carrier_IATA",r."Aircraft_Type_IATA",r."Aircraft_Series_Subtype")=(a."Carrier_IATA",a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype"));
update "Basic_Carrier_Record"."Basic_Aircraft_Data" a set "Non_Standard_Fuel_Loading_Enabled"=true where exists(select 1 from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" r where (r."Carrier_IATA",r."Aircraft_Type_IATA",r."Aircraft_Series_Subtype")=(a."Carrier_IATA",a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype"));

alter table "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD"
 add constraint aircraft_fuel_standard_sg_positive check ("Fuel_Specific_Gravity">0 and "Fuel_Specific_Gravity" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision)),
 add constraint aircraft_fuel_standard_volume_positive check ("Fuel_Volume" is null or "Fuel_Volume">0),
 add constraint aircraft_fuel_standard_weight_positive check ("Fuel_Weight">0),
 add constraint aircraft_fuel_standard_arm_finite check ("H-Arm" is null or "H-Arm" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision)),
 add constraint aircraft_fuel_standard_index_finite check ("Index_Value" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision) and abs("Index_Value")<=1000000000);
alter table "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD"
 add constraint aircraft_fuel_nonstandard_name_valid check ("Tank_Name"=btrim("Tank_Name") and char_length("Tank_Name") between 1 and 80),
 add constraint aircraft_fuel_nonstandard_code_valid check ("Tank_Name_Short_Code" ~ '^[A-Z0-9]{3}$'),
 add constraint aircraft_fuel_nonstandard_sg_positive check ("SG">0 and "SG" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision)),
 add constraint aircraft_fuel_nonstandard_volume_positive check ("Maximum_Volume">0),
 add constraint aircraft_fuel_nonstandard_index_finite check ("Tank_Index_Per_Weight_Unit" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision) and abs("Tank_Index_Per_Weight_Unit")<=1000000000),
 add constraint aircraft_fuel_nonstandard_arm_finite check ("Tank_BA_Centroid" is null or "Tank_BA_Centroid" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision));

create function "Basic_Carrier_Record".get_aircraft_c8(p_iata text,p_type_code text,p_subtype text)
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
  'nonStandard',jsonb_build_object('enabled',aircraft."Non_Standard_Fuel_Loading_Enabled",'rows',coalesce((select jsonb_agg(jsonb_build_object('tankName',"Tank_Name",'tankShortCode',"Tank_Name_Short_Code",'specificGravity',"SG",'maximumVolume',"Maximum_Volume",'indexPerUnitWeight',"Tank_Index_Per_Weight_Unit",'balanceArm',"Tank_BA_Centroid") order by "Tank_Name") from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb)));
 payload:=jsonb_build_object('typeCode',tc,'subtype',st,'weightUnit',units."Weight_Unit",'lengthUnit',units."Length_Unit",'liquidVolumeUnit',units."Liquid_Volume_Unit",'values',values_data);
 return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text));
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c8(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c8(text,text,text) to authenticated;

create function "Basic_Carrier_Record".save_aircraft_c8(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;enabled boolean;rows_data jsonb;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if p_section not in ('standard','nonStandard') or p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'enabled')<>'boolean' or jsonb_typeof(p_values->'rows')<>'array' then raise exception 'Invalid C8 values' using errcode='22023';end if;
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
 if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_c8(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C8 changed' using errcode='40001';end if;
 enabled:=(p_values->>'enabled')::boolean;rows_data:=p_values->'rows';
 if p_section='standard' then
  update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Standard_Fuel_Loading_Enabled"=enabled where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if enabled then
   delete from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
   insert into "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD"("Carrier_IATA","Aircraft_Type_IATA","Fuel_Specific_Gravity","Fuel_Volume","Fuel_Weight","H-Arm","Index_Value","Aircraft_Series_Subtype")
   select p_iata,tc,x."specificGravity",x."fuelVolume",x."fuelWeight",x."hArm",x."indexValue",st from jsonb_to_recordset(rows_data) as x("specificGravity" double precision,"fuelVolume" integer,"fuelWeight" integer,"hArm" double precision,"indexValue" double precision);
  end if;
 else
  update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Non_Standard_Fuel_Loading_Enabled"=enabled where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if enabled then
   delete from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
   insert into "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD"("Carrier_IATA","Aircraft_Type_IATA","Tank_Name","SG","Tank_BA_Centroid","Tank_Index_Per_Weight_Unit","Aircraft_Series_Subtype","Maximum_Volume","Tank_Name_Short_Code")
   select p_iata,tc,x."tankName",x."specificGravity",x."balanceArm",x."indexPerUnitWeight",st,x."maximumVolume",upper(x."tankShortCode") from jsonb_to_recordset(rows_data) as x("tankName" text,"tankShortCode" text,"specificGravity" double precision,"maximumVolume" bigint,"indexPerUnitWeight" double precision,"balanceArm" double precision);
  end if;
 end if;
 return "Basic_Carrier_Record".get_aircraft_c8(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_c8(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c8(text,text,text,text,text,jsonb) to authenticated;
alter policy perm_aircraft_select on "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
alter policy perm_aircraft_insert on "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy perm_aircraft_update on "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy perm_aircraft_delete on "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy perm_aircraft_select on "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
alter policy perm_aircraft_insert on "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy perm_aircraft_update on "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy perm_aircraft_delete on "Basic_Carrier_Record"."Aircraft_Fuel_Loading_NON_STANDARD" using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
notify pgrst,'reload schema';
commit;
