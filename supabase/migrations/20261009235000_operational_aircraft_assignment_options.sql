begin;

alter function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid)
  rename to get_operational_freight_planning_without_assignment_options;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning_without_assignment_options(text,uuid)
  from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".get_operational_freight_planning(
  p_iata text,
  p_operational_flight_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  result jsonb;
  f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
  aircraft "Basic_Carrier_Record"."Basic_Aircraft_Data"%rowtype;
  registrations jsonb;
  crew_codes jsonb;
  pantry_codes jsonb;
begin
  p_iata:=upper(btrim(p_iata));
  result:="Basic_Carrier_Record".get_operational_freight_planning_without_assignment_options(p_iata,p_operational_flight_id);

  select * into f
  from "Basic_Carrier_Record"."Operational_Flights"
  where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;

  select * into aircraft
  from "Basic_Carrier_Record"."Basic_Aircraft_Data"
  where "Carrier_IATA"=p_iata
    and "Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
    and "Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype";

  select coalesce(jsonb_agg(jsonb_build_object(
    'registration',btrim(x."Aircraft_Registration"),
    'weight',case when aircraft."Start_Weight_Principle"='DRY_OPERATING_WEIGHT'
      then x."Dry_Operating_Weight" else x."Basic_Weight" end
  ) order by btrim(x."Aircraft_Registration")),'[]'::jsonb)
  into registrations
  from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" x
  where x."Carrier_IATA"=p_iata
    and x."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
    and x."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype"
    and x."E1_2_Registration_Reference";

  select coalesce(jsonb_agg(jsonb_build_object('code',q.code,'isBase',q.is_base) order by q.code),'[]'::jsonb)
  into crew_codes
  from(
    select btrim(c."Crew_Code_ID") code,bool_or(c."Is_DOW_Base") is_base
    from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
    where c."Carrier_IATA"=p_iata
      and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype"
    group by btrim(c."Crew_Code_ID")
  )q;

  select coalesce(jsonb_agg(jsonb_build_object('code',q.code,'isBase',q.is_base) order by q.code),'[]'::jsonb)
  into pantry_codes
  from(
    select btrim(c."Pantry_Code_ID") code,bool_or(c."Is_DOW_Base") is_base
    from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" c
    where c."Carrier_IATA"=p_iata
      and c."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype"
    group by btrim(c."Pantry_Code_ID")
  )q;

  return result||jsonb_build_object(
    'registrationOptions',registrations,
    'crewOptions',crew_codes,
    'pantryOptions',pantry_codes
  );
end
$$;

revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
