begin;

alter policy "perm_aircraft_select" on "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
alter policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy "perm_aircraft_update" on "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
  with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
alter policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"
  using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_DELETE')));

create or replace function "Basic_Carrier_Record".get_aircraft_c11(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
  can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  row_data "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"%rowtype;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
  select * into row_data from "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  return jsonb_build_object(
    'canView',can_view,'canEdit',can_edit,'exists',row_data."Carrier_IATA" is not null,
    'revision',case when row_data."Carrier_IATA" is null then '' else md5(to_jsonb(row_data)::text) end,
    'typeCode',tc,'subtype',st,
    'values',jsonb_build_object(
      'macFwdLimit',coalesce(row_data."MAC_FWD_Limit",0),
      'macAftLimit',coalesce(row_data."MAC_AFT_Limit",0),
      'stabMaxValue',coalesce(row_data."STAB_MAX_Value",0),
      'stabMinValue',coalesce(row_data."STAB_MIN_Value",0),
      'variationFwd',coalesce(row_data."STAB_VAR_FWD",0),
      'variationAft',coalesce(row_data."STAB_VAR_AFT",0),
      'rateOfChange',coalesce(row_data."STAB_Rate_Of_Change",0)
    )
  );
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c11(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c11(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_c11(p_iata text,p_type_code text,p_subtype text,p_revision text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  current_data jsonb;
  mac_fwd double precision;
  mac_aft double precision;
  stab_max double precision;
  stab_min double precision;
  var_fwd double precision;
  var_aft double precision;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Invalid C11.1 values' using errcode='22023';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
  current_data:="Basic_Carrier_Record".get_aircraft_c11(p_iata,tc,st);
  if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C11.1 changed' using errcode='40001';end if;
  mac_fwd:=(p_values->>'macFwdLimit')::double precision;
  mac_aft:=(p_values->>'macAftLimit')::double precision;
  stab_max:=(p_values->>'stabMaxValue')::double precision;
  stab_min:=(p_values->>'stabMinValue')::double precision;
  var_fwd:=(p_values->>'variationFwd')::double precision;
  var_aft:=(p_values->>'variationAft')::double precision;
  if not (abs(mac_fwd)<=1000000000 and abs(mac_aft)<=1000000000 and abs(stab_max)<=1000000000 and abs(stab_min)<=1000000000 and abs(var_fwd)<=1000000000 and abs(var_aft)<=1000000000 and mac_fwd<=var_fwd and var_fwd<var_aft and var_aft<=mac_aft) then raise exception 'Invalid C11.1 values' using errcode='22023';end if;
  insert into "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","MAC_FWD_Limit","MAC_AFT_Limit","STAB_MAX_Value","STAB_MIN_Value","STAB_VAR_FWD","STAB_VAR_AFT")
  values(p_iata,tc,st,mac_fwd,mac_aft,stab_max,stab_min,var_fwd,var_aft)
  on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set
    "MAC_FWD_Limit"=excluded."MAC_FWD_Limit","MAC_AFT_Limit"=excluded."MAC_AFT_Limit","STAB_MAX_Value"=excluded."STAB_MAX_Value","STAB_MIN_Value"=excluded."STAB_MIN_Value","STAB_VAR_FWD"=excluded."STAB_VAR_FWD","STAB_VAR_AFT"=excluded."STAB_VAR_AFT";
  return "Basic_Carrier_Record".get_aircraft_c11(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_c11(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c11(text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
