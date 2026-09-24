begin;

-- AHM565 C4 uses the aircraft's C1 length unit for Reference Arm, MAC/RC and
-- LEMAC/LERC. Existing values are preserved while exact decimal storage and
-- formula validation are added.
alter table "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
  alter column "Reference_Arm_At" type numeric(14,6) using "Reference_Arm_At"::numeric(14,6),
  alter column "Length_Of_MAC_RC" type numeric(14,6) using "Length_Of_MAC_RC"::numeric(14,6),
  alter column "LEMAC_LERC" type numeric(14,6) using "LEMAC_LERC"::numeric(14,6),
  alter column "Reference_Arm_At" set not null,
  alter column "Constant_K" set not null,
  alter column "Constant_C" set not null,
  alter column "Length_Of_MAC_RC" set not null,
  alter column "LEMAC_LERC" set not null;

alter table "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
  add constraint "carrier_basic_index_mac_reference_arm_range" check (abs("Reference_Arm_At") <= 1000000000),
  add constraint "carrier_basic_index_mac_k_range" check ("Constant_K" between 0 and 1000000000),
  add constraint "carrier_basic_index_mac_c_positive" check ("Constant_C" between 1 and 1000000000),
  add constraint "carrier_basic_index_mac_length_positive" check ("Length_Of_MAC_RC" > 0 and "Length_Of_MAC_RC" <= 1000000000),
  add constraint "carrier_basic_index_mac_lemac_range" check (abs("LEMAC_LERC") <= 1000000000);

alter policy "perm_aircraft_select" on "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
alter policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy "perm_aircraft_update" on "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_DELETE')));

create function "Basic_Carrier_Record".get_aircraft_c4(p_iata text,p_type_code text,p_subtype text)
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

create function "Basic_Carrier_Record".save_aircraft_c4(p_iata text,p_type_code text,p_subtype text,p_revision text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  current_data jsonb;
  ref_arm numeric(14,6);
  k integer;
  c integer;
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
  c:=(p_values->>'constantC')::integer;
  mac_length:=(p_values->>'macRcLength')::numeric(14,6);
  lemac:=(p_values->>'lemacLerc')::numeric(14,6);
  if abs(ref_arm)>1000000000 or k not between 0 and 1000000000 or c not between 1 and 1000000000 or mac_length<=0 or mac_length>1000000000 or abs(lemac)>1000000000 then raise exception 'Invalid C4 values' using errcode='22023';end if;
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
