begin;

alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  add column "Ideal_Trim_Enabled" boolean not null default false,
  add column "Tipping_Limits_Enabled" boolean not null default false;

update "Basic_Carrier_Record"."Basic_Aircraft_Data" aircraft
set "Ideal_Trim_Enabled"=true
where exists(select 1 from "Basic_Carrier_Record"."Aircraft_Ideal_Trim_Line" points where points."Carrier_IATA"=aircraft."Carrier_IATA" and points."Aircraft_Type_IATA"=aircraft."Aircraft_Type_IATA" and points."Aircraft_Series_Subtype"=aircraft."Aircraft_Series_Subtype");

update "Basic_Carrier_Record"."Basic_Aircraft_Data" aircraft
set "Tipping_Limits_Enabled"=true
where exists(select 1 from "Basic_Carrier_Record"."Aircraft_Tipping_Limits" points where points."Carrier_IATA"=aircraft."Carrier_IATA" and points."Aircraft_Type_IATA"=aircraft."Aircraft_Type_IATA" and points."Aircraft_Series_Subtype"=aircraft."Aircraft_Series_Subtype");

alter table "Basic_Carrier_Record"."Aircraft_Ideal_Trim_Line"
  alter column "Value_Index" drop not null,
  add constraint aircraft_ideal_trim_weight_positive check ("Value_Weight">0),
  add constraint aircraft_ideal_trim_value_present check ("Value_Index" is not null or "Value_MAC" is not null),
  add constraint aircraft_ideal_trim_index_finite check ("Value_Index" is null or ("Value_Index" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision) and abs("Value_Index")<=1000000000)),
  add constraint aircraft_ideal_trim_mac_range check ("Value_MAC" is null or ("Value_MAC" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision) and "Value_MAC" between 0 and 100));

do $$ declare primary_name text; begin
  select constraint_name into primary_name from information_schema.table_constraints where table_schema='Basic_Carrier_Record' and table_name='Aircraft_Tipping_Limits' and constraint_type='PRIMARY KEY';
  if primary_name is not null then execute format('alter table "Basic_Carrier_Record"."Aircraft_Tipping_Limits" drop constraint %I',primary_name); end if;
end $$;

alter table "Basic_Carrier_Record"."Aircraft_Tipping_Limits"
  alter column "Tipping_Envelope_Weight" set not null,
  add constraint aircraft_tipping_limits_pkey primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Tipping_Envelope_Weight"),
  add constraint aircraft_tipping_weight_positive check ("Tipping_Envelope_Weight">0),
  add constraint aircraft_tipping_value_present check ("Tipping_Envelope_Index" is not null or "Tipping_Envelope_MAC" is not null),
  add constraint aircraft_tipping_index_finite check ("Tipping_Envelope_Index" is null or ("Tipping_Envelope_Index" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision) and abs("Tipping_Envelope_Index")<=1000000000)),
  add constraint aircraft_tipping_mac_range check ("Tipping_Envelope_MAC" is null or ("Tipping_Envelope_MAC" not in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision) and "Tipping_Envelope_MAC" between 0 and 100));

create function private.c7_points_valid(p_points jsonb,p_maximum integer)
returns boolean language sql immutable set search_path='' as $$
  select jsonb_typeof(p_points)='array' and jsonb_array_length(p_points)>=1
    and not exists(
      select 1 from jsonb_to_recordset(p_points) as x(weight numeric,"indexValue" numeric,"macValue" numeric)
      where weight is null or weight<=0 or weight<>trunc(weight)
         or (p_maximum is not null and weight>p_maximum)
         or ("indexValue" is null and "macValue" is null)
         or ("indexValue" is not null and abs("indexValue")>1000000000)
         or ("macValue" is not null and "macValue" not between 0 and 100)
    )
    and (select count(*)=count(distinct weight) from jsonb_to_recordset(p_points) as x(weight numeric));
$$;
revoke all on function private.c7_points_valid(jsonb,integer) from public,anon;
grant execute on function private.c7_points_valid(jsonb,integer) to authenticated;

create function "Basic_Carrier_Record".get_aircraft_c7(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');aircraft "Basic_Carrier_Record"."Basic_Aircraft_Data"%rowtype;weight_unit text;values_data jsonb;payload jsonb;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
  select * into aircraft from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if aircraft."Carrier_IATA" is null then raise exception 'Aircraft not found' using errcode='23503';end if;
  select "Weight_Unit" into weight_unit from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if weight_unit is null then raise exception 'Complete C1 first' using errcode='23503';end if;
  values_data:=jsonb_build_object(
    'idealTrim',jsonb_build_object('enabled',aircraft."Ideal_Trim_Enabled",'points',coalesce((select jsonb_agg(jsonb_build_object('weight',"Value_Weight",'indexValue',"Value_Index",'macValue',"Value_MAC") order by "Value_Weight") from "Basic_Carrier_Record"."Aircraft_Ideal_Trim_Line" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb)),
    'tippingLimits',jsonb_build_object('enabled',aircraft."Tipping_Limits_Enabled",'points',coalesce((select jsonb_agg(jsonb_build_object('weight',"Tipping_Envelope_Weight",'indexValue',"Tipping_Envelope_Index",'macValue',"Tipping_Envelope_MAC") order by "Tipping_Envelope_Weight") from "Basic_Carrier_Record"."Aircraft_Tipping_Limits" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),'[]'::jsonb)));
  payload:=jsonb_build_object('typeCode',tc,'subtype',st,'weightUnit',weight_unit,'maximumRampWeight',aircraft."MRW",'values',values_data);
  return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text));
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c7(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c7(text,text,text) to authenticated;

create function "Basic_Carrier_Record".save_aircraft_c7(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;enabled boolean;points jsonb;maximum_weight integer;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
  if p_section not in ('idealTrim','tippingLimits') or p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'enabled')<>'boolean' or jsonb_typeof(p_values->'points')<>'array' then raise exception 'Invalid C7 values' using errcode='22023';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
  current_data:="Basic_Carrier_Record".get_aircraft_c7(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C7 changed' using errcode='40001';end if;
  enabled:=(p_values->>'enabled')::boolean;points:=p_values->'points';select "MRW" into maximum_weight from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  if enabled and not private.c7_points_valid(points,maximum_weight) then raise exception 'Invalid C7 points or Weight exceeds MRW' using errcode='23514';end if;
  if p_section='idealTrim' then
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Ideal_Trim_Enabled"=enabled where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    if enabled then delete from "Basic_Carrier_Record"."Aircraft_Ideal_Trim_Line" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;insert into "Basic_Carrier_Record"."Aircraft_Ideal_Trim_Line"("Carrier_IATA","Aircraft_Type_IATA","Value_Weight","Value_Index","Value_MAC","Aircraft_Series_Subtype") select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(points) as x(weight integer,"indexValue" double precision,"macValue" double precision);end if;
  else
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Tipping_Limits_Enabled"=enabled where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    if enabled then delete from "Basic_Carrier_Record"."Aircraft_Tipping_Limits" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;insert into "Basic_Carrier_Record"."Aircraft_Tipping_Limits"("Carrier_IATA","Aircraft_Type_IATA","Tipping_Envelope_Weight","Tipping_Envelope_Index","Tipping_Envelope_MAC","Aircraft_Series_Subtype") select p_iata,tc,x.weight,x."indexValue",x."macValue",st from jsonb_to_recordset(points) as x(weight integer,"indexValue" double precision,"macValue" double precision);end if;
  end if;
  return "Basic_Carrier_Record".get_aircraft_c7(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_c7(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c7(text,text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
