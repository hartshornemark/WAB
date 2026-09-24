begin;

alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  add column "Balance_Envelope_Input_Mode" varchar(5) not null default 'INDEX',
  add constraint "basic_aircraft_balance_envelope_input_mode"
    check ("Balance_Envelope_Input_Mode" in ('INDEX','MAC'));

create or replace function private.c5_calculate_envelope_pair()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
declare
  selected_mode text;
  reference_arm numeric;
  constant_k numeric;
  constant_c numeric;
  mac_length numeric;
  lemac numeric;
begin
  select aircraft."Balance_Envelope_Input_Mode", formula."Reference_Arm_At",
         formula."Constant_K", formula."Constant_C", formula."Length_Of_MAC_RC",
         formula."LEMAC_LERC"
    into selected_mode, reference_arm, constant_k, constant_c, mac_length, lemac
    from "Basic_Carrier_Record"."Basic_Aircraft_Data" aircraft
    join "Basic_Carrier_Record"."Carrier_Basic_Index_MAC" formula
      on formula."Carrier_IATA"=aircraft."Carrier_IATA"
     and formula."Aircraft_Type_IATA"=aircraft."Aircraft_Type_IATA"
     and formula."Aircraft_Series_Subtype"=aircraft."Aircraft_Series_Subtype"
   where aircraft."Carrier_IATA"=new."Carrier_IATA"
     and aircraft."Aircraft_Type_IATA"=new."Aircraft_Type_IATA"
     and aircraft."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype";

  if selected_mode is null or constant_c is null or constant_c=0 or mac_length is null or mac_length=0 then
    raise exception 'Complete the C4 formula before saving C5.1 envelope points' using errcode='23514';
  end if;
  if new."Aircraft_Weight" is null or new."Aircraft_Weight"<=0 then
    raise exception 'C5.1 envelope Weight must be positive' using errcode='23514';
  end if;

  if selected_mode='INDEX' then
    if new."Envelope_Limit_Index_Value" is null then
      raise exception 'Enter the C5.1 Index value' using errcode='23514';
    end if;
    new."Envelope_Limit_MAC_Value":=round((
      ((constant_c*(new."Envelope_Limit_Index_Value"-constant_k)/new."Aircraft_Weight"+reference_arm-lemac)/mac_length)*100
    )::numeric,6)::double precision;
  else
    if new."Envelope_Limit_MAC_Value" is null then
      raise exception 'Enter the C5.1 %%MAC value' using errcode='23514';
    end if;
    new."Envelope_Limit_Index_Value":=round((
      new."Aircraft_Weight"*((lemac+mac_length*new."Envelope_Limit_MAC_Value"/100)-reference_arm)/constant_c+constant_k
    )::numeric,6)::double precision;
  end if;
  return new;
end $$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW','Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW',
    'Aircraft_Centre_Of_Gravity_Limits_FWD_TOW','Aircraft_Centre_Of_Gravity_Limits_AFT_TOW',
    'Aircraft_Centre_Of_Gravity_Limits_FWD_LAW','Aircraft_Centre_Of_Gravity_Limits_AFT_LAW'
  ] loop
    execute format('drop trigger if exists c5_calculate_envelope_pair on "Basic_Carrier_Record".%I',table_name);
    execute format('create trigger c5_calculate_envelope_pair before insert or update of "Aircraft_Weight","Envelope_Limit_Index_Value","Envelope_Limit_MAC_Value" on "Basic_Carrier_Record".%I for each row execute function private.c5_calculate_envelope_pair()',table_name);
  end loop;
end $$;

create or replace function "Basic_Carrier_Record".get_aircraft_c5_input_mode(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));selected_mode text;
begin
  if (select auth.uid()) is null or not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')) then
    raise exception 'Not authorised' using errcode='42501';
  end if;
  select "Balance_Envelope_Input_Mode" into selected_mode
    from "Basic_Carrier_Record"."Basic_Aircraft_Data"
   where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if selected_mode is null then raise exception 'Aircraft not found' using errcode='23503';end if;
  return jsonb_build_object('inputMode',selected_mode);
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c5_input_mode(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c5_input_mode(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_c5_status(p_iata text,p_type_code text,p_subtype text,p_revision text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;
  curtailed boolean;selected_mode text;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then
    raise exception 'Not authorised' using errcode='42501';
  end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Invalid C5.1 status' using errcode='22023';end if;

  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data"
   where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
  current_data:="Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);
  if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C5.1 changed' using errcode='40001';end if;

  if p_values->'curtailed'='null'::jsonb then curtailed:=null;
  elsif jsonb_typeof(p_values->'curtailed')='boolean' then curtailed:=(p_values->>'curtailed')::boolean;
  else raise exception 'Invalid curtailed status' using errcode='22023';end if;
  selected_mode:=p_values->>'inputMode';
  if selected_mode not in ('INDEX','MAC') then raise exception 'Invalid C5.1 input mode' using errcode='22023';end if;

  update "Basic_Carrier_Record"."Basic_Aircraft_Data"
     set "Balance_Envelope_Curtailed"=curtailed,"Balance_Envelope_Input_Mode"=selected_mode
   where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;

  if selected_mode='INDEX' then
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_TOW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_LAW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_LAW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  else
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW" set "Envelope_Limit_MAC_Value"="Envelope_Limit_MAC_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_TOW" set "Envelope_Limit_MAC_Value"="Envelope_Limit_MAC_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_LAW" set "Envelope_Limit_MAC_Value"="Envelope_Limit_MAC_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_LAW" set "Envelope_Limit_MAC_Value"="Envelope_Limit_MAC_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW" set "Envelope_Limit_MAC_Value"="Envelope_Limit_MAC_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW" set "Envelope_Limit_MAC_Value"="Envelope_Limit_MAC_Value" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  end if;
  return "Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_c5_status(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c5_status(text,text,text,text,jsonb) to authenticated;

-- Existing envelopes were recorded as Index, so calculate their corresponding %MAC.
update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value";
update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_TOW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value";
update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_LAW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value";
update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_LAW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value";
update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value";
update only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW" set "Envelope_Limit_Index_Value"="Envelope_Limit_Index_Value";

notify pgrst,'reload schema';
commit;
