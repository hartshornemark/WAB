begin;

create or replace function "Basic_Carrier_Record".save_operational_freight_planning(
  p_iata text,
  p_operational_flight_id uuid,
  p_version integer,
  p_values jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
  weight_basis text:=upper(btrim(p_values->>'weightBasis'));
  registration text:=nullif(upper(btrim(p_values->>'registration')),'');
  crew_code text:=nullif(upper(btrim(p_values->>'crewCode')),'');
  pantry_code text:=nullif(upper(btrim(p_values->>'pantryCode')),'');
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not(
    private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')
    or private.has_global_permission('LOAD_CONTROL_OPERATE')
  ) then raise exception 'Load Control operation denied' using errcode='42501';end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' or weight_basis not in('FLEET_WEIGHT','REGISTRATION')
    or crew_code!~'^[A-Z0-9]$' or pantry_code!~'^[A-Z0-9]$'
    or (weight_basis='REGISTRATION' and registration is null)
    or (weight_basis='FLEET_WEIGHT' and registration is not null)
  then raise exception 'Check the aircraft assignment selections' using errcode='22023';end if;

  select * into f from "Basic_Carrier_Record"."Operational_Flights"
  where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
  if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
  if f."Version"<>p_version then raise exception 'The flight changed. Reload before saving.' using errcode='40001';end if;
  if weight_basis='REGISTRATION' and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" x
    where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and x."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and x."E1_2_Registration_Reference"
      and btrim(x."Aircraft_Registration")=registration)
  then raise exception 'Select a valid aircraft registration' using errcode='23503';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and btrim(c."Crew_Code_ID")=crew_code)
  then raise exception 'Select a valid crew code' using errcode='23503';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and btrim(c."Pantry_Code_ID")=pantry_code)
  then raise exception 'Select a valid pantry code' using errcode='23503';end if;

  update "Basic_Carrier_Record"."Operational_Flights" set
    "Aircraft_Registration"=registration,"Crew_Code_ID"=crew_code,"Pantry_Code_ID"=pantry_code,
    "Status"=case when "Status"='INITIATED' then 'LOAD_PLANNING' else "Status" end
  where "Operational_Flight_ID"=p_operational_flight_id and "Carrier_IATA"=p_iata;
  return "Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);
end;
$$;

revoke all on function "Basic_Carrier_Record".save_operational_freight_planning(text,uuid,integer,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_freight_planning(text,uuid,integer,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
