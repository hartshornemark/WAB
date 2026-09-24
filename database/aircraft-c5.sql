begin;

alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  add constraint "basic_aircraft_maximum_weight_order" check (
    ("MZFW" is null or "MLAW" is null or "MZFW"<="MLAW") and
    ("MLAW" is null or "MTOW" is null or "MLAW"<="MTOW") and
    ("MTOW" is null or "MRW" is null or "MTOW"<="MRW")
  );

-- These five tables were created as PostgreSQL inheritance children of the
-- FWD TOW table. That makes an ordinary FWD TOW query return every C5.1
-- boundary. Detaching inheritance preserves every physical row and restores
-- the six independent datasets intended by AHM565 C5.1.
alter table "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_LAW" no inherit "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW";
alter table "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_TOW" no inherit "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW";
alter table "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW" no inherit "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW";
alter table "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_LAW" no inherit "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW";
alter table "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW" no inherit "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW";

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW','Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW',
    'Aircraft_Centre_Of_Gravity_Limits_FWD_TOW','Aircraft_Centre_Of_Gravity_Limits_AFT_TOW',
    'Aircraft_Centre_Of_Gravity_Limits_FWD_LAW','Aircraft_Centre_Of_Gravity_Limits_AFT_LAW'
  ] loop
    execute format('alter table "Basic_Carrier_Record".%I add constraint %I check ("Aircraft_Weight">0)',table_name,lower(table_name)||'_weight_positive');
    execute format('alter table "Basic_Carrier_Record".%I add constraint %I check ("Envelope_Limit_Index_Value" not in (''NaN''::double precision,''Infinity''::double precision,''-Infinity''::double precision) and abs("Envelope_Limit_Index_Value")<=1000000000)',table_name,lower(table_name)||'_index_finite');
    execute format('alter table "Basic_Carrier_Record".%I add constraint %I check ("Envelope_Limit_MAC_Value" is null or ("Envelope_Limit_MAC_Value" not in (''NaN''::double precision,''Infinity''::double precision,''-Infinity''::double precision) and "Envelope_Limit_MAC_Value" between 0 and 100))',table_name,lower(table_name)||'_mac_range');
    execute format('alter policy perm_aircraft_select on "Basic_Carrier_Record".%I using ((select private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_VIEW'')) or (select private.has_global_permission(''AIRCRAFT_CONFIG_VIEW'')))',table_name);
    execute format('alter policy perm_aircraft_insert on "Basic_Carrier_Record".%I with check ((select private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_EDIT'')) or (select private.has_global_permission(''AIRCRAFT_CONFIG_EDIT'')))',table_name);
    execute format('alter policy perm_aircraft_update on "Basic_Carrier_Record".%I using ((select private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_EDIT'')) or (select private.has_global_permission(''AIRCRAFT_CONFIG_EDIT''))) with check ((select private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_EDIT'')) or (select private.has_global_permission(''AIRCRAFT_CONFIG_EDIT'')))',table_name);
    execute format('alter policy perm_aircraft_delete on "Basic_Carrier_Record".%I using ((select private.has_carrier_permission("Carrier_IATA",''AIRCRAFT_CONFIG_EDIT'')) or (select private.has_global_permission(''AIRCRAFT_CONFIG_EDIT'')))',table_name);
  end loop;
end $$;

create function private.c5_points_valid(p_points jsonb,p_maximum integer)
returns boolean language sql immutable set search_path='' as $$
  select jsonb_array_length(p_points)>=2
    and p_maximum>0
    and not exists(
      select 1 from jsonb_to_recordset(p_points) as x(weight numeric,"indexValue" numeric,"macValue" numeric)
      where weight is null or weight<=0 or weight<>trunc(weight) or weight>p_maximum
         or "indexValue" is null or abs("indexValue")>1000000000
         or ("macValue" is not null and "macValue" not between 0 and 100)
    )
    and (select count(*)=count(distinct weight) from jsonb_to_recordset(p_points) as x(weight numeric))
    and (select max(weight)=p_maximum from jsonb_to_recordset(p_points) as x(weight integer));
$$;
revoke all on function private.c5_points_valid(jsonb,integer) from public,anon;
grant execute on function private.c5_points_valid(jsonb,integer) to authenticated;

create function "Basic_Carrier_Record".get_aircraft_c5(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');aircraft "Basic_Carrier_Record"."Basic_Aircraft_Data"%rowtype;weight_unit text;values_data jsonb;payload jsonb;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
  select * into aircraft from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if aircraft."Carrier_IATA" is null then raise exception 'Aircraft not found' using errcode='23503';end if;
  select "Weight_Unit" into weight_unit from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if weight_unit is null then raise exception 'Complete C1 first' using errcode='23503';end if;
  values_data:=jsonb_build_object('curtailed',aircraft."Balance_Envelope_Curtailed",'maximumWeights',jsonb_build_object('mrw',coalesce(aircraft."MRW",0),'tow',coalesce(aircraft."MTOW",0),'law',coalesce(aircraft."MLAW",0),'zfw',coalesce(aircraft."MZFW",0)),'envelopes',jsonb_build_object(
    'tow',jsonb_build_object(
      'fwd',coalesce((select jsonb_agg(jsonb_build_object('weight',"Aircraft_Weight",'indexValue',"Envelope_Limit_Index_Value",'macValue',"Envelope_Limit_MAC_Value") order by "Aircraft_Weight") from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb),
      'aft',coalesce((select jsonb_agg(jsonb_build_object('weight',"Aircraft_Weight",'indexValue',"Envelope_Limit_Index_Value",'macValue',"Envelope_Limit_MAC_Value") order by "Aircraft_Weight") from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_TOW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb)),
    'law',jsonb_build_object(
      'fwd',coalesce((select jsonb_agg(jsonb_build_object('weight',"Aircraft_Weight",'indexValue',"Envelope_Limit_Index_Value",'macValue',"Envelope_Limit_MAC_Value") order by "Aircraft_Weight") from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_LAW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb),
      'aft',coalesce((select jsonb_agg(jsonb_build_object('weight',"Aircraft_Weight",'indexValue',"Envelope_Limit_Index_Value",'macValue',"Envelope_Limit_MAC_Value") order by "Aircraft_Weight") from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_LAW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb)),
    'zfw',jsonb_build_object(
      'fwd',coalesce((select jsonb_agg(jsonb_build_object('weight',"Aircraft_Weight",'indexValue',"Envelope_Limit_Index_Value",'macValue',"Envelope_Limit_MAC_Value") order by "Aircraft_Weight") from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb),
      'aft',coalesce((select jsonb_agg(jsonb_build_object('weight',"Aircraft_Weight",'indexValue',"Envelope_Limit_Index_Value",'macValue',"Envelope_Limit_MAC_Value") order by "Aircraft_Weight") from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb))));
  payload:=jsonb_build_object('typeCode',tc,'subtype',st,'weightUnit',weight_unit,'values',values_data);
  return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text));
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c5(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c5(text,text,text) to authenticated;

create function "Basic_Carrier_Record".save_aircraft_c5(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;mrw_max integer;tow_max integer;law_max integer;zfw_max integer;curtailed boolean;tow_fwd jsonb;tow_aft jsonb;law_fwd jsonb;law_aft jsonb;zfw_fwd jsonb;zfw_aft jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' or p_section not in ('status','mrw','tow','law','zfw') then raise exception 'Invalid C5.1 values' using errcode='22023';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
  current_data:="Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C5.1 changed' using errcode='40001';end if;
  mrw_max:=(p_values#>>'{maximumWeights,mrw}')::integer;tow_max:=(p_values#>>'{maximumWeights,tow}')::integer;law_max:=(p_values#>>'{maximumWeights,law}')::integer;zfw_max:=(p_values#>>'{maximumWeights,zfw}')::integer;
  if mrw_max>0 and tow_max>mrw_max then raise exception 'MTOW cannot be greater than MRW' using errcode='23514';end if;
  if tow_max>0 and law_max>tow_max then raise exception 'MLAW cannot be greater than MTOW' using errcode='23514';end if;
  if law_max>0 and zfw_max>law_max then raise exception 'MZFW cannot be greater than MLAW' using errcode='23514';end if;
  if p_values->'curtailed'='null'::jsonb then curtailed:=null;elsif jsonb_typeof(p_values->'curtailed')='boolean' then curtailed:=(p_values->>'curtailed')::boolean;else raise exception 'Invalid curtailed status' using errcode='22023';end if;
  tow_fwd:=p_values#>'{envelopes,tow,fwd}';tow_aft:=p_values#>'{envelopes,tow,aft}';law_fwd:=p_values#>'{envelopes,law,fwd}';law_aft:=p_values#>'{envelopes,law,aft}';zfw_fwd:=p_values#>'{envelopes,zfw,fwd}';zfw_aft:=p_values#>'{envelopes,zfw,aft}';
  if p_section='status' then
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Balance_Envelope_Curtailed"=curtailed where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  elsif p_section='mrw' then
    if mrw_max<=0 then raise exception 'Invalid MRW' using errcode='23514';end if;
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "MRW"=mrw_max where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  elsif p_section='tow' then
    if jsonb_typeof(tow_fwd)<>'array' or jsonb_typeof(tow_aft)<>'array' or not private.c5_points_valid(tow_fwd,tow_max) or not private.c5_points_valid(tow_aft,tow_max) then raise exception 'Final TOW FWD and AFT weights must equal MTOW' using errcode='23514';end if;
    delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_TOW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(tow_fwd) as x(weight integer,"indexValue" double precision,"macValue" double precision);insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_TOW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(tow_aft) as x(weight integer,"indexValue" double precision,"macValue" double precision);
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "MTOW"=tow_max where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  elsif p_section='law' then
    if jsonb_typeof(law_fwd)<>'array' or jsonb_typeof(law_aft)<>'array' or not private.c5_points_valid(law_fwd,law_max) or not private.c5_points_valid(law_aft,law_max) then raise exception 'Final LAW FWD and AFT weights must equal MLAW' using errcode='23514';end if;
    delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_LAW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_LAW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_LAW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(law_fwd) as x(weight integer,"indexValue" double precision,"macValue" double precision);insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_LAW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(law_aft) as x(weight integer,"indexValue" double precision,"macValue" double precision);
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "MLAW"=law_max where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  else
    if jsonb_typeof(zfw_fwd)<>'array' or jsonb_typeof(zfw_aft)<>'array' or not private.c5_points_valid(zfw_fwd,zfw_max) or not private.c5_points_valid(zfw_aft,zfw_max) then raise exception 'Final ZFW FWD and AFT weights must equal MZFW' using errcode='23514';end if;
    delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(zfw_fwd) as x(weight integer,"indexValue" double precision,"macValue" double precision);insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(zfw_aft) as x(weight integer,"indexValue" double precision,"macValue" double precision);
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "MZFW"=zfw_max where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  end if;
  return "Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_c5(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c5(text,text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
