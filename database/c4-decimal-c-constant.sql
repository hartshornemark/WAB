begin;

alter table "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
  drop constraint "carrier_basic_index_mac_c_positive",
  add constraint "carrier_basic_index_mac_c_positive" check ("Constant_C" > 0 and "Constant_C" <= 1000000000);

create or replace function "Basic_Carrier_Record".save_aircraft_c4(p_iata text,p_type_code text,p_subtype text,p_revision text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  current_data jsonb;
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
  ref_arm:=(p_values->>'referenceArm')::numeric(14,6);
  k:=(p_values->>'constantK')::integer;
  c:=(p_values->>'constantC')::numeric(14,6);
  mac_length:=(p_values->>'macRcLength')::numeric(14,6);
  lemac:=(p_values->>'lemacLerc')::numeric(14,6);
  if abs(ref_arm)>1000000000 or k not between 0 and 1000000000 or c<=0 or c>1000000000 or mac_length<=0 or mac_length>1000000000 or abs(lemac)>1000000000 then raise exception 'Invalid C4 values' using errcode='22023';end if;
  insert into "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Reference_Arm_At","Constant_K","Constant_C","Length_Of_MAC_RC","LEMAC_LERC")
  values(p_iata,tc,st,ref_arm,k,c,mac_length,lemac)
  on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set
    "Reference_Arm_At"=excluded."Reference_Arm_At","Constant_K"=excluded."Constant_K","Constant_C"=excluded."Constant_C",
    "Length_Of_MAC_RC"=excluded."Length_Of_MAC_RC","LEMAC_LERC"=excluded."LEMAC_LERC";
  return "Basic_Carrier_Record".get_aircraft_c4(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".save_aircraft_c4(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c4(text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
