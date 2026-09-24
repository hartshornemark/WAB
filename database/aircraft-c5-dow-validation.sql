begin;

create or replace function private.aircraft_effective_dow(p_iata text,p_type_code text,p_subtype text)
returns integer language sql stable security invoker set search_path='' as $$
  select coalesce(
    (select min(f."Dry_Operating_Weight") from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f
      where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=upper(btrim(p_type_code))
        and f."Aircraft_Series_Subtype"=upper(btrim(p_subtype)) and f."Dry_Operating_Weight">0),
    (select case when a."Standard_Fleet_Weight">0 then a."Standard_Fleet_Weight" end
      from "Basic_Carrier_Record"."Basic_Aircraft_Data" a
      where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=upper(btrim(p_type_code))
        and a."Aircraft_Series_Subtype"=upper(btrim(p_subtype))),0)::integer;
$$;
revoke all on function private.aircraft_effective_dow(text,text,text) from public,anon;
grant execute on function private.aircraft_effective_dow(text,text,text) to authenticated;

create or replace function private.c5_points_valid(p_points jsonb,p_maximum integer,p_effective_dow integer)
returns boolean language sql immutable set search_path='' as $$
  select jsonb_typeof(p_points)='array'
    and jsonb_array_length(p_points)>=2
    and p_maximum>0 and p_effective_dow>0
    and not exists(
      select 1 from jsonb_to_recordset(p_points) as x(weight numeric,"indexValue" numeric,"macValue" numeric)
      where weight is null or weight<=0 or weight<>trunc(weight) or weight>p_maximum
         or "indexValue" is null or abs("indexValue")>1000000000
         or ("macValue" is not null and "macValue" not between 0 and 100)
    )
    and (select count(*)=count(distinct weight) from jsonb_to_recordset(p_points) as x(weight numeric))
    and (select min(weight)<=p_effective_dow from jsonb_to_recordset(p_points) as x(weight integer));
$$;
revoke all on function private.c5_points_valid(jsonb,integer,integer) from public,anon;
grant execute on function private.c5_points_valid(jsonb,integer,integer) to authenticated;

create or replace function "Basic_Carrier_Record".get_aircraft_c5_effective_dow(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));fleet_dow integer;standard_weight integer;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
  select min("Dry_Operating_Weight") into fleet_dow from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=upper(btrim(p_type_code)) and "Aircraft_Series_Subtype"=upper(btrim(p_subtype)) and "Dry_Operating_Weight">0;
  select "Standard_Fleet_Weight" into standard_weight from "Basic_Carrier_Record"."Basic_Aircraft_Data"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=upper(btrim(p_type_code)) and "Aircraft_Series_Subtype"=upper(btrim(p_subtype));
  if fleet_dow is not null then return jsonb_build_object('value',fleet_dow,'source','fleet');end if;
  if standard_weight>0 then return jsonb_build_object('value',standard_weight,'source','standard');end if;
  return jsonb_build_object('value',0,'source','unavailable');
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c5_effective_dow(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c5_effective_dow(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_c5(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;
  mrw_max integer;tow_max integer;law_max integer;zfw_max integer;effective_dow integer;curtailed boolean;
  tow_fwd jsonb;tow_aft jsonb;law_fwd jsonb;law_aft jsonb;zfw_fwd jsonb;zfw_aft jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' or p_section not in ('status','mrw','towMaximum','lawMaximum','zfwMaximum','tow','law','zfw') then raise exception 'Invalid C5.1 values' using errcode='22023';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
  current_data:="Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C5.1 changed' using errcode='40001';end if;
  mrw_max:=(p_values#>>'{maximumWeights,mrw}')::integer;tow_max:=(p_values#>>'{maximumWeights,tow}')::integer;law_max:=(p_values#>>'{maximumWeights,law}')::integer;zfw_max:=(p_values#>>'{maximumWeights,zfw}')::integer;
  effective_dow:=private.aircraft_effective_dow(p_iata,tc,st);if effective_dow<=0 then raise exception 'Configure a fleet DOW or Standard Fleet Weight' using errcode='23514';end if;
  if effective_dow>zfw_max then raise exception 'DOW cannot be greater than MZFW' using errcode='23514';end if;
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
  elsif p_section='towMaximum' then
    if tow_max<=0 then raise exception 'Invalid MTOW' using errcode='23514';end if;
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "MTOW"=tow_max where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  elsif p_section='lawMaximum' then
    if law_max<=0 then raise exception 'Invalid MLAW' using errcode='23514';end if;
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "MLAW"=law_max where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  elsif p_section='zfwMaximum' then
    if zfw_max<=0 then raise exception 'Invalid MZFW' using errcode='23514';end if;
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "MZFW"=zfw_max where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  elsif p_section='tow' then
    if not private.c5_points_valid(tow_fwd,tow_max,effective_dow) or not private.c5_points_valid(tow_aft,tow_max,effective_dow) then raise exception 'Check every TOW envelope point' using errcode='23514';end if;
    delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_TOW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_TOW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(tow_fwd) as x(weight integer,"indexValue" double precision,"macValue" double precision);insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_TOW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(tow_aft) as x(weight integer,"indexValue" double precision,"macValue" double precision);
  elsif p_section='law' then
    if not private.c5_points_valid(law_fwd,law_max,effective_dow) or not private.c5_points_valid(law_aft,law_max,effective_dow) then raise exception 'Check every LAW envelope point' using errcode='23514';end if;
    delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_LAW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_LAW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_LAW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(law_fwd) as x(weight integer,"indexValue" double precision,"macValue" double precision);insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_LAW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(law_aft) as x(weight integer,"indexValue" double precision,"macValue" double precision);
  else
    if not private.c5_points_valid(zfw_fwd,zfw_max,effective_dow) or not private.c5_points_valid(zfw_aft,zfw_max,effective_dow) then raise exception 'Check every ZFW envelope point' using errcode='23514';end if;
    delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;delete from only "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_FWD_ZFW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(zfw_fwd) as x(weight integer,"indexValue" double precision,"macValue" double precision);insert into "Basic_Carrier_Record"."Aircraft_Centre_Of_Gravity_Limits_AFT_ZFW" select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(zfw_aft) as x(weight integer,"indexValue" double precision,"macValue" double precision);
  end if;
  return "Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_c5(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c5(text,text,text,text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
