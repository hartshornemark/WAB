begin;

alter table "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"
  add column if not exists "STAB_Method" text not null default 'LINEAR',
  add column if not exists "STAB_Matrix" jsonb not null default '{"macColumns":[],"rows":[]}'::jsonb;

do $$ begin
  alter table "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"
    add constraint "Aircraft_Stabiliser_TRIM_Settings_method_check" check ("STAB_Method" in ('LINEAR','MATRIX'));
exception when duplicate_object then null; end $$;

create or replace function "Basic_Carrier_Record".get_aircraft_c11(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));
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
      'method',coalesce(row_data."STAB_Method",'LINEAR'),
      'macFwdLimit',coalesce(row_data."MAC_FWD_Limit",0),'macAftLimit',coalesce(row_data."MAC_AFT_Limit",0),
      'stabMaxValue',coalesce(row_data."STAB_MAX_Value",0),'stabMinValue',coalesce(row_data."STAB_MIN_Value",0),
      'variationFwd',coalesce(row_data."STAB_VAR_FWD",0),'variationAft',coalesce(row_data."STAB_VAR_AFT",0),
      'rateOfChange',coalesce(row_data."STAB_Rate_Of_Change",0),
      'macColumns',coalesce(row_data."STAB_Matrix"->'macColumns','[]'::jsonb),
      'rows',coalesce(row_data."STAB_Matrix"->'rows','[]'::jsonb)
    )
  );
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c11(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c11(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_c11(p_iata text,p_type_code text,p_subtype text,p_revision text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;
  method text:=upper(coalesce(p_values->>'method','LINEAR'));matrix_data jsonb:='{"macColumns":[],"rows":[]}'::jsonb;
  mac_fwd double precision;mac_aft double precision;stab_max double precision;stab_min double precision;var_fwd double precision;var_aft double precision;
  column_count integer;row_count integer;numeric_count integer;previous_value double precision;current_value double precision;item jsonb;cell jsonb;values_data jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' or method not in ('LINEAR','MATRIX') then raise exception 'Invalid C11.1 values' using errcode='22023';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
  current_data:="Basic_Carrier_Record".get_aircraft_c11(p_iata,tc,st);
  if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C11.1 changed' using errcode='40001';end if;

  if method='LINEAR' then
    mac_fwd:=(p_values->>'macFwdLimit')::double precision;mac_aft:=(p_values->>'macAftLimit')::double precision;
    stab_max:=(p_values->>'stabMaxValue')::double precision;stab_min:=(p_values->>'stabMinValue')::double precision;
    var_fwd:=(p_values->>'variationFwd')::double precision;var_aft:=(p_values->>'variationAft')::double precision;
    if not (abs(mac_fwd)<=1000000000 and abs(mac_aft)<=1000000000 and abs(stab_max)<=1000000000 and abs(stab_min)<=1000000000 and abs(var_fwd)<=1000000000 and abs(var_aft)<=1000000000 and mac_fwd<=var_fwd and var_fwd<var_aft and var_aft<=mac_aft) then raise exception 'Invalid C11.1 values' using errcode='22023';end if;
  else
    if jsonb_typeof(p_values->'macColumns')<>'array' or jsonb_typeof(p_values->'rows')<>'array' then raise exception 'Invalid C11.1 matrix' using errcode='22023';end if;
    column_count:=jsonb_array_length(p_values->'macColumns');row_count:=jsonb_array_length(p_values->'rows');
    if column_count<2 or column_count>50 or row_count<2 or row_count>200 then raise exception 'Invalid C11.1 matrix size' using errcode='22023';end if;
    previous_value:=null;
    for cell in select value from jsonb_array_elements(p_values->'macColumns') loop
      if jsonb_typeof(cell)<>'number' then raise exception 'Invalid C11.1 MAC column' using errcode='22023';end if;
      current_value:=(cell#>>'{}')::double precision;
      if abs(current_value)>1000000000 or (previous_value is not null and current_value<=previous_value) then raise exception 'Invalid C11.1 MAC order' using errcode='22023';end if;
      previous_value:=current_value;
    end loop;
    previous_value:=null;
    for item in select value from jsonb_array_elements(p_values->'rows') loop
      if jsonb_typeof(item)<>'object' or jsonb_typeof(item->'tow')<>'number' or jsonb_typeof(item->'trimValues')<>'array' or jsonb_array_length(item->'trimValues')<>column_count then raise exception 'Invalid C11.1 matrix row' using errcode='22023';end if;
      current_value:=(item->>'tow')::double precision;
      if current_value<=0 or current_value<>trunc(current_value) or current_value>1000000000 or (previous_value is not null and current_value<=previous_value) then raise exception 'Invalid C11.1 TOW order' using errcode='22023';end if;
      previous_value:=current_value;numeric_count:=0;values_data:=item->'trimValues';
      for cell in select value from jsonb_array_elements(values_data) loop
        if jsonb_typeof(cell)='number' then current_value:=(cell#>>'{}')::double precision;numeric_count:=numeric_count+1;if abs(current_value)>1000000000 then raise exception 'Invalid C11.1 trim value' using errcode='22023';end if;
        elsif jsonb_typeof(cell)<>'null' then raise exception 'Invalid C11.1 trim cell' using errcode='22023';end if;
      end loop;
      if numeric_count<2 then raise exception 'Incomplete C11.1 matrix row' using errcode='22023';end if;
    end loop;
    for column_count in 0..jsonb_array_length(p_values->'macColumns')-1 loop
      if not exists(select 1 from jsonb_array_elements(p_values->'rows') r where jsonb_typeof(r->'trimValues'->column_count)='number') then raise exception 'Empty C11.1 matrix column' using errcode='22023';end if;
    end loop;
    matrix_data:=jsonb_build_object('macColumns',p_values->'macColumns','rows',p_values->'rows');
    mac_fwd:=(p_values->'macColumns'->>0)::double precision;mac_aft:=(p_values->'macColumns'->>(jsonb_array_length(p_values->'macColumns')-1))::double precision;var_fwd:=mac_fwd;var_aft:=mac_aft;
    select max((v#>>'{}')::double precision),min((v#>>'{}')::double precision) into stab_max,stab_min from jsonb_array_elements(p_values->'rows') r cross join lateral jsonb_array_elements(r->'trimValues') v where jsonb_typeof(v)='number';
  end if;
  insert into "Basic_Carrier_Record"."Aircraft_Stabiliser_TRIM_Settings"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","MAC_FWD_Limit","MAC_AFT_Limit","STAB_MAX_Value","STAB_MIN_Value","STAB_VAR_FWD","STAB_VAR_AFT","STAB_Method","STAB_Matrix")
  values(p_iata,tc,st,mac_fwd,mac_aft,stab_max,stab_min,var_fwd,var_aft,method,matrix_data)
  on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set
    "MAC_FWD_Limit"=excluded."MAC_FWD_Limit","MAC_AFT_Limit"=excluded."MAC_AFT_Limit","STAB_MAX_Value"=excluded."STAB_MAX_Value","STAB_MIN_Value"=excluded."STAB_MIN_Value","STAB_VAR_FWD"=excluded."STAB_VAR_FWD","STAB_VAR_AFT"=excluded."STAB_VAR_AFT","STAB_Method"=excluded."STAB_Method","STAB_Matrix"=excluded."STAB_Matrix";
  return "Basic_Carrier_Record".get_aircraft_c11(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_c11(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c11(text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
