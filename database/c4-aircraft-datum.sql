begin;

alter table "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
  add column if not exists "Balance_Arm_At_Nose" numeric(14,6) not null default 0;

alter table "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
  add constraint "carrier_basic_index_mac_datum_range"
  check (abs("Balance_Arm_At_Nose") <= 1000000000);

update "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
set "Balance_Arm_At_Nose" = case
  when "Carrier_IATA"='ZZ' and "Aircraft_Type_IATA"='319' and "Aircraft_Series_Subtype"='100' then 2.540
  when "Carrier_IATA"='AB' and "Aircraft_Type_IATA"='320' and "Aircraft_Series_Subtype"='200' then 0.000
  else "Balance_Arm_At_Nose"
end
where ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") in
  (('ZZ','319','100'),('AB','320','200'));

create or replace function "Basic_Carrier_Record".get_aircraft_c4(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
  can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  row_data "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"%rowtype;
  length_unit text;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
  select "Length_Unit" into length_unit from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if length_unit is null then raise exception 'Complete C1 first' using errcode='23503';end if;
  select * into row_data from "Basic_Carrier_Record"."Carrier_Basic_Index_MAC" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  return jsonb_build_object(
    'canView',can_view,'canEdit',can_edit,'exists',row_data."Carrier_IATA" is not null,
    'revision',case when row_data."Carrier_IATA" is null then '' else md5(to_jsonb(row_data)::text||length_unit) end,
    'typeCode',tc,'subtype',st,'lengthUnit',length_unit,
    'values',jsonb_build_object(
      'datum',coalesce(row_data."Balance_Arm_At_Nose",0),
      'referenceArm',coalesce(row_data."Reference_Arm_At",0),
      'constantK',coalesce(row_data."Constant_K",0),
      'constantC',coalesce(row_data."Constant_C",0),
      'macRcLength',coalesce(row_data."Length_Of_MAC_RC",0),
      'lemacLerc',coalesce(row_data."LEMAC_LERC",0)
    )
  );
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_c4(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c4(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_c4(p_iata text,p_type_code text,p_subtype text,p_revision text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  current_data jsonb;
  datum_value numeric(14,6);
  ref_arm numeric(14,6);
  k integer;
  c numeric(14,6);
  mac_length numeric(14,6);
  lemac numeric(14,6);
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Invalid C4 values' using errcode='22023';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
  current_data:="Basic_Carrier_Record".get_aircraft_c4(p_iata,tc,st);
  if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C4 changed' using errcode='40001';end if;
  datum_value:=(p_values->>'datum')::numeric(14,6);
  ref_arm:=(p_values->>'referenceArm')::numeric(14,6);
  k:=(p_values->>'constantK')::integer;
  c:=(p_values->>'constantC')::numeric(14,6);
  mac_length:=(p_values->>'macRcLength')::numeric(14,6);
  lemac:=(p_values->>'lemacLerc')::numeric(14,6);
  if abs(datum_value)>1000000000 or abs(ref_arm)>1000000000 or k not between 0 and 1000000000 or c<=0 or c>1000000000 or mac_length<=0 or mac_length>1000000000 or abs(lemac)>1000000000 then raise exception 'Invalid C4 values' using errcode='22023';end if;
  insert into "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Balance_Arm_At_Nose","Reference_Arm_At","Constant_K","Constant_C","Length_Of_MAC_RC","LEMAC_LERC")
  values(p_iata,tc,st,datum_value,ref_arm,k,c,mac_length,lemac)
  on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set
    "Balance_Arm_At_Nose"=excluded."Balance_Arm_At_Nose","Reference_Arm_At"=excluded."Reference_Arm_At","Constant_K"=excluded."Constant_K","Constant_C"=excluded."Constant_C",
    "Length_Of_MAC_RC"=excluded."Length_Of_MAC_RC","LEMAC_LERC"=excluded."LEMAC_LERC";
  return "Basic_Carrier_Record".get_aircraft_c4(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".save_aircraft_c4(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c4(text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
