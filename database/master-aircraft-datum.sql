begin;

alter table "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
  add column if not exists "Balance_Arm_At_Nose" numeric(14,6) not null default 0;

alter table "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
  add constraint "master_aircraft_type_datum_range"
  check (abs("Balance_Arm_At_Nose") <= 1000000000);

update "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
set "Balance_Arm_At_Nose" = case
  when "Aircraft_Type_IATA"='319' and "Aircraft_Series_Subtype"='100' then 2.540
  when "Aircraft_Type_IATA"='320' and "Aircraft_Series_Subtype"='200' then 0.000
  else "Balance_Arm_At_Nose"
end
where ("Aircraft_Type_IATA","Aircraft_Series_Subtype") in
  (('319','100'),('320','200'));

create or replace function "Basic_Carrier_Record".get_aircraft_c4(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
  can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  row_data "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"%rowtype;
  master_datum numeric(14,6);
  length_unit text;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
  select "Balance_Arm_At_Nose" into master_datum
  from "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
  where "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if not found or not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
  select "Length_Unit" into length_unit from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if length_unit is null then raise exception 'Complete C1 first' using errcode='23503';end if;
  select * into row_data from "Basic_Carrier_Record"."Carrier_Basic_Index_MAC" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  return jsonb_build_object(
    'canView',can_view,'canEdit',can_edit,'exists',row_data."Carrier_IATA" is not null,
    'revision',case when row_data."Carrier_IATA" is null then '' else md5(to_jsonb(row_data)::text||length_unit) end,
    'typeCode',tc,'subtype',st,'lengthUnit',length_unit,
    'values',jsonb_build_object(
      'datum',coalesce(row_data."Balance_Arm_At_Nose",master_datum,0),
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

notify pgrst,'reload schema';
commit;
