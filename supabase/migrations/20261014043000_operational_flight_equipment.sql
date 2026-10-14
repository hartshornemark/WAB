begin;

create or replace function private.touch_operational_flight()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  new."Updated_At":=now();
  new."Updated_By":=coalesce(auth.uid(),old."Updated_By");
  new."Version":=old."Version"+1;
  return new;
end;
$$;

revoke all on function private.touch_operational_flight() from public,anon,authenticated;

create or replace function private.default_operational_flight_configuration()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new."Aircraft_Configuration" is null then
    select btrim(c."Configuration_Code")
    into new."Aircraft_Configuration"
    from "Basic_Carrier_Record"."Aircraft_Configurations" c
    where c."Carrier_IATA"=new."Carrier_IATA"
      and c."Aircraft_Type_IATA"=new."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype"
      and c."Is_Default"
    order by c."Configuration_Code"
    limit 1;
  end if;
  return new;
end;
$$;

revoke all on function private.default_operational_flight_configuration() from public,anon,authenticated;

drop trigger if exists "default_operational_flight_configuration" on "Basic_Carrier_Record"."Operational_Flights";
create trigger "default_operational_flight_configuration"
before insert on "Basic_Carrier_Record"."Operational_Flights"
for each row execute function private.default_operational_flight_configuration();

with defaults as (
  select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",min(btrim("Configuration_Code")) configuration_code
  from "Basic_Carrier_Record"."Aircraft_Configurations"
  where "Is_Default"
  group by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"
)
update "Basic_Carrier_Record"."Operational_Flights" f
set "Aircraft_Configuration"=defaults.configuration_code
from defaults
where f."Aircraft_Configuration" is null
  and defaults."Carrier_IATA"=f."Carrier_IATA"
  and defaults."Aircraft_Type_IATA"=f."Aircraft_Type_IATA"
  and defaults."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype";

create or replace function "Basic_Carrier_Record".save_operational_flight_equipment(
  p_iata text,
  p_operational_flight_id uuid,
  p_expected_version integer,
  p_aircraft_type text,
  p_aircraft_subtype text,
  p_aircraft_configuration text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
  saved "Basic_Carrier_Record"."Operational_Flights"%rowtype;
  configuration text:=nullif(upper(btrim(p_aircraft_configuration)),'');
  type_code text:=upper(btrim(p_aircraft_type));
  subtype_code text:=upper(btrim(p_aircraft_subtype));
  registration text;
  crew text;
  pantry text;
  role text;
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not(
    private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')
    or private.has_global_permission('LOAD_CONTROL_OPERATE')
  ) then raise exception 'Load Control operation denied' using errcode='42501';end if;

  select * into f
  from "Basic_Carrier_Record"."Operational_Flights"
  where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id
  for update;
  if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
  if f."Version"<>p_expected_version then raise exception 'The operational flight changed. Reload before saving the aircraft type and configuration.' using errcode='40001';end if;
  if type_code!~'^[A-Z0-9]{2,4}$' or subtype_code!~'^[A-Z0-9]{1,4}$' or configuration is not null and configuration!~'^[A-Z]$'
    then raise exception 'Select a valid aircraft type and cabin configuration' using errcode='22023';end if;

  select a."Aircraft_Operating_Role" into role
  from "Basic_Carrier_Record"."Basic_Aircraft_Data" a
  where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=type_code and a."Aircraft_Series_Subtype"=subtype_code;
  if not found then raise exception 'Select an aircraft type configured for this carrier' using errcode='23503';end if;

  if configuration is null then
    select btrim(c."Configuration_Code") into configuration
    from "Basic_Carrier_Record"."Aircraft_Configurations" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=type_code and c."Aircraft_Series_Subtype"=subtype_code
      and c."Is_Default"
    order by c."Configuration_Code"
    limit 1;
  end if;
  if exists(
    select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=type_code and c."Aircraft_Series_Subtype"=subtype_code
  ) and (configuration is null or not exists(
    select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=type_code and c."Aircraft_Series_Subtype"=subtype_code
      and btrim(c."Configuration_Code")=configuration
  )) then raise exception 'Select a cabin configuration defined on AHM565 D9 for this aircraft type' using errcode='23503';end if;

  if (f."Aircraft_Type_IATA",f."Aircraft_Series_Subtype",f."Aircraft_Configuration") is distinct from (type_code,subtype_code,configuration)
    and exists(select 1 from "Basic_Carrier_Record"."Operational_Load_Plan_Editions" p where p."Operational_Flight_ID"=p_operational_flight_id)
    then raise exception 'The aircraft type and configuration cannot change after a load-plan edition has been saved' using errcode='55000';end if;

  registration:=f."Aircraft_Registration";
  crew:=btrim(f."Crew_Code_ID");
  pantry:=btrim(f."Pantry_Code_ID");
  if (f."Aircraft_Type_IATA",f."Aircraft_Series_Subtype") is distinct from (type_code,subtype_code) then
    if registration is not null and not exists(
      select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" fleet
      where fleet."Carrier_IATA"=p_iata and fleet."Aircraft_Type_IATA"=type_code and fleet."Aircraft_Series_Subtype"=subtype_code
        and fleet."E1_2_Registration_Reference" and btrim(fleet."Aircraft_Registration")=registration
    ) then registration:=null;end if;
    if crew is not null and not exists(
      select 1 from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
      where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=type_code and c."Aircraft_Series_Subtype"=subtype_code and btrim(c."Crew_Code_ID")=crew
    ) then crew:=null;end if;
    if pantry is not null and not exists(
      select 1 from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" c
      where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=type_code and c."Aircraft_Series_Subtype"=subtype_code and btrim(c."Pantry_Code_ID")=pantry
    ) then pantry:=null;end if;
    if crew is null then
      select min(btrim(c."Crew_Code_ID")) into crew from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
      where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=type_code and c."Aircraft_Series_Subtype"=subtype_code
      having count(distinct btrim(c."Crew_Code_ID"))=1;
    end if;
    if pantry is null then
      select min(btrim(c."Pantry_Code_ID")) into pantry from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" c
      where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=type_code and c."Aircraft_Series_Subtype"=subtype_code
      having count(distinct btrim(c."Pantry_Code_ID"))=1;
    end if;
  end if;

  update "Basic_Carrier_Record"."Operational_Flights"
  set "Aircraft_Type_IATA"=type_code,
      "Aircraft_Series_Subtype"=subtype_code,
      "Aircraft_Configuration"=configuration,
      "Aircraft_Registration"=registration,
      "Crew_Code_ID"=crew,
      "Pantry_Code_ID"=pantry,
      "Passenger_Weight_Basis"=case when role='FREIGHTER' then null else coalesce(f."Passenger_Weight_Basis",'STANDARD') end,
      "Passenger_Flight_Variation"=case when role='FREIGHTER' or (f."Aircraft_Type_IATA",f."Aircraft_Series_Subtype") is distinct from (type_code,subtype_code) then null else f."Passenger_Flight_Variation" end,
      "Baggage_Weight_Basis"=case when role='FREIGHTER' then null else coalesce(f."Baggage_Weight_Basis",'STANDARD') end,
      "Baggage_Flight_Variation"=case when role='FREIGHTER' or (f."Aircraft_Type_IATA",f."Aircraft_Series_Subtype") is distinct from (type_code,subtype_code) then null else f."Baggage_Flight_Variation" end
  where "Operational_Flight_ID"=p_operational_flight_id and "Carrier_IATA"=p_iata
  returning * into saved;

  return jsonb_build_object(
    'aircraftType',saved."Aircraft_Type_IATA",
    'aircraftSubtype',saved."Aircraft_Series_Subtype",
    'aircraftConfiguration',saved."Aircraft_Configuration",
    'registration',saved."Aircraft_Registration",
    'version',saved."Version"
  );
end;
$$;

revoke all on function "Basic_Carrier_Record".save_operational_flight_equipment(text,uuid,integer,text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_flight_equipment(text,uuid,integer,text,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
