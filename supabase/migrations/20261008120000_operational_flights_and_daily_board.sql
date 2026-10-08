begin;

insert into application_security.permissions(permission_code,permission_name,description)
values
  ('LOAD_CONTROL_VIEW','View Load Control','View operational flights and the Daily Load Control board'),
  ('LOAD_CONTROL_OPERATE','Operate Load Control','Start scheduled flights and create or maintain operational flight instances')
on conflict(permission_code) do update
set permission_name=excluded.permission_name,
    description=excluded.description,
    active=true;

insert into application_security.role_permissions(role_id,permission_id)
select r.role_id,p.permission_id
from application_security.roles r
cross join application_security.permissions p
where r.role_code in ('SOLUTION_ADMINISTRATOR','CARRIER_ADMINISTRATOR','CONFIGURATION_EDITOR')
  and p.permission_code in ('LOAD_CONTROL_VIEW','LOAD_CONTROL_OPERATE')
on conflict do nothing;

create table "Basic_Carrier_Record"."Operational_Flights"(
  "Operational_Flight_ID" uuid primary key default gen_random_uuid(),
  "Carrier_IATA" varchar(2) not null
    references "Basic_Carrier_Record"."MASTER_Carrier_Contact"("Carrier_IATA")
    on update cascade on delete restrict,
  "Schedule_Leg_ID" uuid
    references "Basic_Carrier_Record"."Scheduled_Flight_Legs"("Schedule_Leg_ID")
    on update cascade on delete restrict,
  "Service_Date" date not null,
  "Source_Type" text not null check("Source_Type" in('SCHEDULED','AD_HOC')),
  "Airline_Designator" varchar(3) not null check("Airline_Designator" ~ '^[A-Z0-9]{2,3}$'),
  "Flight_Number" varchar(4) not null check("Flight_Number" ~ '^(?:[0-9]{1,4}|[0-9]{1,3}[A-Z])$'),
  "Operational_Suffix" varchar(1) not null default '' check("Operational_Suffix" ~ '^[A-Z0-9]?$'),
  "Itinerary_Variation_Identifier" varchar(8) not null default '01',
  "Leg_Sequence_Number" smallint not null default 1 check("Leg_Sequence_Number" between 1 and 99),
  "Itinerary_Key" text not null check(char_length("Itinerary_Key") between 1 and 300),
  "Itinerary_Snapshot" jsonb not null check(jsonb_typeof("Itinerary_Snapshot")='object'),
  "Service_Type" varchar(1) not null check("Service_Type" ~ '^[A-Z0-9]$'),
  "Departure_Airport_IATA" char(3) not null
    references "Basic_Carrier_Record"."MASTER_Airports"("Airport_IATA")
    on update cascade on delete restrict,
  "Arrival_Airport_IATA" char(3) not null
    references "Basic_Carrier_Record"."MASTER_Airports"("Airport_IATA")
    on update cascade on delete restrict,
  "Scheduled_Departure_Local" timestamp without time zone not null,
  "Scheduled_Arrival_Local" timestamp without time zone not null,
  "Estimated_Departure_Local" timestamp without time zone,
  "Estimated_Arrival_Local" timestamp without time zone,
  "Departure_UTC_Offset_Minutes" smallint check("Departure_UTC_Offset_Minutes" between -840 and 840),
  "Arrival_UTC_Offset_Minutes" smallint check("Arrival_UTC_Offset_Minutes" between -840 and 840),
  "Departure_Terminal" varchar(8),
  "Arrival_Terminal" varchar(8),
  "Aircraft_Type_IATA" varchar(4) not null check("Aircraft_Type_IATA" ~ '^[A-Z0-9]{2,4}$'),
  "Aircraft_Series_Subtype" varchar(4) not null check("Aircraft_Series_Subtype" ~ '^[A-Z0-9]{1,4}$'),
  "Aircraft_Configuration" varchar(3),
  "Aircraft_Registration" varchar(10) check("Aircraft_Registration" is null or "Aircraft_Registration" ~ '^[A-Z0-9][A-Z0-9-]{0,9}$'),
  "Crew_Code_ID" varchar(1) check("Crew_Code_ID" is null or "Crew_Code_ID" ~ '^[A-Z0-9]$'),
  "Pantry_Code_ID" varchar(1) check("Pantry_Code_ID" is null or "Pantry_Code_ID" ~ '^[A-Z0-9]$'),
  "Passenger_Weight_Basis" text check("Passenger_Weight_Basis" is null or "Passenger_Weight_Basis" in('STANDARD','VARIATION','ACTUAL')),
  "Passenger_Flight_Variation" varchar(3),
  "Baggage_Weight_Basis" text check("Baggage_Weight_Basis" is null or "Baggage_Weight_Basis" in('STANDARD','VARIATION','ACTUAL')),
  "Baggage_Flight_Variation" varchar(3),
  "Status" text not null default 'INITIATED'
    check("Status" in('INITIATED','LOAD_PLANNING','LOADSHEET_PRELIMINARY','LOADSHEET_FINAL','CLOSED','CANCELLED')),
  "Priority" text not null default 'NORMAL' check("Priority" in('NORMAL','HIGH')),
  "Remarks" text check("Remarks" is null or char_length("Remarks")<=2000),
  "Schedule_Snapshot" jsonb not null default '{}'::jsonb check(jsonb_typeof("Schedule_Snapshot")='object'),
  "Version" integer not null default 1 check("Version">0),
  "Started_By" uuid not null default auth.uid(),
  "Started_At" timestamptz not null default now(),
  "Updated_By" uuid not null default auth.uid(),
  "Updated_At" timestamptz not null default now(),
  constraint "operational_flight_route_check" check("Departure_Airport_IATA"<>"Arrival_Airport_IATA"),
  constraint "operational_flight_time_check" check("Scheduled_Arrival_Local">"Scheduled_Departure_Local"),
  constraint "operational_flight_source_check" check(
    ("Source_Type"='SCHEDULED' and "Schedule_Leg_ID" is not null)
    or ("Source_Type"='AD_HOC' and "Schedule_Leg_ID" is null)
  )
);

create unique index "operational_flight_schedule_date_unique"
  on "Basic_Carrier_Record"."Operational_Flights"("Schedule_Leg_ID","Service_Date")
  where "Schedule_Leg_ID" is not null;

create unique index "operational_flight_ad_hoc_identity_unique"
  on "Basic_Carrier_Record"."Operational_Flights"(
    "Carrier_IATA","Service_Date","Airline_Designator","Flight_Number","Operational_Suffix",
    "Leg_Sequence_Number","Departure_Airport_IATA","Arrival_Airport_IATA"
  ) where "Source_Type"='AD_HOC' and "Status"<>'CANCELLED';

create index "operational_flights_daily_board_idx"
  on "Basic_Carrier_Record"."Operational_Flights"(
    "Carrier_IATA","Service_Date","Scheduled_Departure_Local","Status"
  );

create index "operational_flights_registration_idx"
  on "Basic_Carrier_Record"."Operational_Flights"(
    "Carrier_IATA","Aircraft_Registration","Service_Date"
  ) where "Aircraft_Registration" is not null;

create table "Basic_Carrier_Record"."Operational_Flight_Events"(
  "Event_ID" bigint generated always as identity primary key,
  "Operational_Flight_ID" uuid not null
    references "Basic_Carrier_Record"."Operational_Flights"("Operational_Flight_ID")
    on update cascade on delete cascade,
  "Carrier_IATA" varchar(2) not null,
  "Event_Type" text not null check("Event_Type" in('CREATED','STATUS_CHANGED','UPDATED')),
  "Previous_Status" text,
  "New_Status" text,
  "Event_Data" jsonb not null default '{}'::jsonb check(jsonb_typeof("Event_Data")='object'),
  "Actor_User_ID" uuid not null default auth.uid(),
  "Occurred_At" timestamptz not null default now()
);

create index "operational_flight_events_flight_time_idx"
  on "Basic_Carrier_Record"."Operational_Flight_Events"(
    "Operational_Flight_ID","Occurred_At" desc
  );

create index "operational_flight_events_carrier_time_idx"
  on "Basic_Carrier_Record"."Operational_Flight_Events"(
    "Carrier_IATA","Occurred_At" desc
  );

comment on table "Basic_Carrier_Record"."Operational_Flights" is
  'Mutable flight instances for one operating date. Scheduled rows reference an immutable schedule leg; ad-hoc rows are independent.';
comment on table "Basic_Carrier_Record"."Operational_Flight_Events" is
  'Append-only audit history for operational flight creation and workflow changes.';

alter table "Basic_Carrier_Record"."Operational_Flights" enable row level security;
alter table "Basic_Carrier_Record"."Operational_Flight_Events" enable row level security;

grant select on "Basic_Carrier_Record"."Operational_Flights" to authenticated;
grant select on "Basic_Carrier_Record"."Operational_Flight_Events" to authenticated;

create policy "operational_flights_select"
on "Basic_Carrier_Record"."Operational_Flights"
for select to authenticated
using(
  (select private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW'))
  or (select private.has_global_permission('LOAD_CONTROL_VIEW'))
);

create policy "operational_flight_events_select"
on "Basic_Carrier_Record"."Operational_Flight_Events"
for select to authenticated
using(
  (select private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW'))
  or (select private.has_global_permission('LOAD_CONTROL_VIEW'))
);

create or replace function private.touch_operational_flight()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  new."Updated_At":=now();
  new."Updated_By":=auth.uid();
  new."Version":=old."Version"+1;
  return new;
end;
$$;

revoke all on function private.touch_operational_flight() from public,anon,authenticated;

create trigger "touch_operational_flight"
before update on "Basic_Carrier_Record"."Operational_Flights"
for each row execute function private.touch_operational_flight();

create or replace function private.audit_operational_flight()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  insert into "Basic_Carrier_Record"."Operational_Flight_Events"(
    "Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data","Actor_User_ID"
  ) values(
    new."Operational_Flight_ID",
    new."Carrier_IATA",
    case when tg_op='INSERT' then 'CREATED' when old."Status" is distinct from new."Status" then 'STATUS_CHANGED' else 'UPDATED' end,
    case when tg_op='UPDATE' then old."Status" end,
    new."Status",
    jsonb_build_object('version',new."Version",'sourceType',new."Source_Type"),
    coalesce(auth.uid(),new."Updated_By")
  );
  return new;
end;
$$;

revoke all on function private.audit_operational_flight() from public,anon,authenticated;

create trigger "audit_operational_flight"
after insert or update on "Basic_Carrier_Record"."Operational_Flights"
for each row execute function private.audit_operational_flight();

create or replace function private.operational_itinerary_snapshot(
  p_schedule_leg_id uuid,
  p_service_date date
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with target as(
  select l.*
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l
  where l."Schedule_Leg_ID"=p_schedule_leg_id
), candidates as(
  select distinct on(l."Leg_Sequence_Number")
    l."Schedule_Leg_ID",l."Leg_Sequence_Number",btrim(l."Departure_Airport_IATA") departure_airport,
    btrim(l."Arrival_Airport_IATA") arrival_airport,l."Departure_Time_Local",l."Arrival_Time_Local",
    l."Arrival_Day_Offset",l."Aircraft_Type_IATA",l."Aircraft_Series_Subtype",l."Aircraft_Configuration"
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l
  join target t on t."Import_ID"=l."Import_ID"
    and t."Airline_Designator"=l."Airline_Designator"
    and t."Flight_Number"=l."Flight_Number"
    and t."Operational_Suffix"=l."Operational_Suffix"
    and t."Itinerary_Variation_Identifier"=l."Itinerary_Variation_Identifier"
    and t."Service_Type"=l."Service_Type"
  order by l."Leg_Sequence_Number",
    case when p_service_date between l."Period_Start_Date" and l."Period_End_Date" then 0 else 1 end,
    abs(p_service_date-l."Period_Start_Date"),l."Period_Start_Date" desc
), identity as(
  select t."Import_ID",t."Airline_Designator",t."Flight_Number",t."Operational_Suffix",
    t."Itinerary_Variation_Identifier",t."Service_Type"
  from target t
), route as(
  select min(c.departure_airport) filter(where c."Leg_Sequence_Number"=(select min("Leg_Sequence_Number") from candidates))
    ||' → '||string_agg(c.arrival_airport,' → ' order by c."Leg_Sequence_Number") value
  from candidates c
)
select jsonb_build_object(
  'key',concat_ws('|',i."Import_ID"::text,i."Airline_Designator",i."Flight_Number",i."Operational_Suffix",i."Itinerary_Variation_Identifier",i."Service_Type"),
  'route',r.value,
  'legs',coalesce((select jsonb_agg(jsonb_build_object(
    'scheduleLegId',c."Schedule_Leg_ID",'legSequence',c."Leg_Sequence_Number",
    'departureAirport',c.departure_airport,'arrivalAirport',c.arrival_airport,
    'departureTime',to_char(c."Departure_Time_Local",'HH24:MI'),
    'arrivalTime',to_char(c."Arrival_Time_Local",'HH24:MI'),
    'arrivalDayOffset',c."Arrival_Day_Offset",'aircraftType',c."Aircraft_Type_IATA",
    'aircraftSubtype',c."Aircraft_Series_Subtype",'aircraftConfiguration',c."Aircraft_Configuration",
    'current',c."Schedule_Leg_ID"=p_schedule_leg_id
  ) order by c."Leg_Sequence_Number") from candidates c),'[]'::jsonb)
)
from identity i cross join route r;
$$;

revoke all on function private.operational_itinerary_snapshot(uuid,date) from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".start_operational_flight(
  p_iata text,
  p_schedule_leg_id uuid,
  p_service_date date
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  leg record;
  parameters record;
  itinerary jsonb;
  operational_id uuid;
  departure_offset smallint;
  arrival_offset smallint;
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not(
    private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')
    or private.has_global_permission('LOAD_CONTROL_OPERATE')
  ) then raise exception 'Load Control operation denied' using errcode='42501';end if;
  if p_service_date is null then raise exception 'Select a service date' using errcode='22023';end if;

  select l.*,i."Original_File_Name",i."Source_Format",i."Status" import_status
  into leg
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l
  join "Basic_Carrier_Record"."Flight_Schedule_Imports" i on i."Import_ID"=l."Import_ID"
  where l."Schedule_Leg_ID"=p_schedule_leg_id and l."Carrier_IATA"=p_iata
    and i."Status"='PUBLISHED'
    and p_service_date between l."Period_Start_Date" and l."Period_End_Date"
    and get_bit(l."Operating_Days",extract(isodow from p_service_date)::integer-1)=1;
  if not found then raise exception 'The scheduled flight is not operating on this date' using errcode='P0002';end if;

  select p.* into parameters
  from "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p
  where p."Schedule_Leg_ID"=p_schedule_leg_id;
  if not found then raise exception 'Complete the schedule Load Control parameters before starting this flight' using errcode='55000';end if;

  departure_offset:=case when leg."Source_Format"='MANUAL' and nullif(leg."Additional_Data"->>'departureTimeZone','') is not null
    then private.local_utc_offset_minutes(p_service_date+leg."Departure_Time_Local",leg."Additional_Data"->>'departureTimeZone')
    else leg."Departure_UTC_Offset_Minutes" end;
  arrival_offset:=case when leg."Source_Format"='MANUAL' and nullif(leg."Additional_Data"->>'arrivalTimeZone','') is not null
    then private.local_utc_offset_minutes(p_service_date+leg."Arrival_Day_Offset"+leg."Arrival_Time_Local",leg."Additional_Data"->>'arrivalTimeZone')
    else leg."Arrival_UTC_Offset_Minutes" end;
  itinerary:=private.operational_itinerary_snapshot(p_schedule_leg_id,p_service_date);

  insert into "Basic_Carrier_Record"."Operational_Flights"(
    "Carrier_IATA","Schedule_Leg_ID","Service_Date","Source_Type","Airline_Designator","Flight_Number",
    "Operational_Suffix","Itinerary_Variation_Identifier","Leg_Sequence_Number","Itinerary_Key","Itinerary_Snapshot",
    "Service_Type","Departure_Airport_IATA","Arrival_Airport_IATA","Scheduled_Departure_Local","Scheduled_Arrival_Local",
    "Estimated_Departure_Local","Estimated_Arrival_Local","Departure_UTC_Offset_Minutes","Arrival_UTC_Offset_Minutes",
    "Departure_Terminal","Arrival_Terminal","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Configuration",
    "Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation",
    "Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Schedule_Snapshot"
  ) values(
    p_iata,p_schedule_leg_id,p_service_date,'SCHEDULED',leg."Airline_Designator",leg."Flight_Number",
    leg."Operational_Suffix",leg."Itinerary_Variation_Identifier",leg."Leg_Sequence_Number",itinerary->>'key',itinerary,
    leg."Service_Type",leg."Departure_Airport_IATA",leg."Arrival_Airport_IATA",p_service_date+leg."Departure_Time_Local",
    p_service_date+leg."Arrival_Day_Offset"+leg."Arrival_Time_Local",p_service_date+leg."Departure_Time_Local",
    p_service_date+leg."Arrival_Day_Offset"+leg."Arrival_Time_Local",departure_offset,arrival_offset,
    leg."Departure_Terminal",leg."Arrival_Terminal",leg."Aircraft_Type_IATA",parameters."Aircraft_Series_Subtype",
    leg."Aircraft_Configuration",btrim(parameters."Crew_Code_ID"),btrim(parameters."Pantry_Code_ID"),
    parameters."Passenger_Weight_Basis",parameters."Passenger_Flight_Variation",
    parameters."Baggage_Weight_Basis",parameters."Baggage_Flight_Variation",parameters."Remarks",
    jsonb_build_object('importId',leg."Import_ID",'scheduleName',leg."Original_File_Name",'scheduleAdditionalData',leg."Additional_Data")
  )
  on conflict("Schedule_Leg_ID","Service_Date") where "Schedule_Leg_ID" is not null do nothing
  returning "Operational_Flight_ID" into operational_id;

  if operational_id is null then
    select f."Operational_Flight_ID" into operational_id
    from "Basic_Carrier_Record"."Operational_Flights" f
    where f."Schedule_Leg_ID"=p_schedule_leg_id and f."Service_Date"=p_service_date;
  end if;
  return operational_id;
end;
$$;

revoke all on function "Basic_Carrier_Record".start_operational_flight(text,uuid,date) from public,anon;
grant execute on function "Basic_Carrier_Record".start_operational_flight(text,uuid,date) to authenticated;

create or replace function "Basic_Carrier_Record".create_ad_hoc_operational_flight(
  p_iata text,
  p_values jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  service_date date;
  flight_number text;
  operational_suffix text;
  service_type text;
  departure_airport text;
  arrival_airport text;
  departure_time time;
  arrival_time time;
  arrival_day smallint;
  aircraft_type text;
  aircraft_subtype text;
  aircraft_configuration text;
  aircraft_registration text;
  remarks text;
  departure_zone text;
  arrival_zone text;
  departure_local timestamp;
  arrival_local timestamp;
  crew_code text;
  pantry_code text;
  operational_id uuid;
  itinerary jsonb;
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not(
    private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')
    or private.has_global_permission('LOAD_CONTROL_OPERATE')
  ) then raise exception 'Load Control operation denied' using errcode='42501';end if;
  if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Ad-hoc flight details are required' using errcode='22023';end if;

  service_date:=(p_values->>'serviceDate')::date;
  flight_number:=upper(btrim(p_values->>'flightNumber'));
  operational_suffix:=upper(btrim(coalesce(p_values->>'operationalSuffix','')));
  service_type:=upper(btrim(p_values->>'serviceType'));
  departure_airport:=upper(btrim(p_values->>'departureAirport'));
  arrival_airport:=upper(btrim(p_values->>'arrivalAirport'));
  departure_time:=(p_values->>'departureTime')::time;
  arrival_time:=(p_values->>'arrivalTime')::time;
  arrival_day:=coalesce((p_values->>'arrivalDayOffset')::smallint,0);
  aircraft_type:=upper(btrim(p_values->>'aircraftType'));
  aircraft_subtype:=upper(btrim(p_values->>'aircraftSubtype'));
  aircraft_configuration:=nullif(upper(btrim(p_values->>'aircraftConfiguration')),'');
  aircraft_registration:=nullif(upper(btrim(p_values->>'aircraftRegistration')),'');
  remarks:=nullif(btrim(p_values->>'remarks'),'');

  if flight_number!~'^(?:[0-9]{1,4}|[0-9]{1,3}[A-Z])$' or operational_suffix!~'^[A-Z0-9]?$'
    or service_type!~'^[A-Z0-9]$' or departure_airport!~'^[A-Z]{3}$' or arrival_airport!~'^[A-Z]{3}$'
    or departure_airport=arrival_airport or arrival_day not between 0 and 2
    or aircraft_type!~'^[A-Z0-9]{2,4}$' or aircraft_subtype!~'^[A-Z0-9]{1,4}$'
    or aircraft_registration is not null and aircraft_registration!~'^[A-Z0-9][A-Z0-9-]{0,9}$'
    or remarks is not null and char_length(remarks)>2000
  then raise exception 'Check every ad-hoc flight value' using errcode='22023';end if;

  if not exists(select 1 from "Basic_Carrier_Record"."MASTER_Flight_Service_Types" s where s."Service_Type_Code"=service_type and s."Active")
    then raise exception 'Select a valid service type' using errcode='23503';end if;
  select a."IANA_Time_Zone" into departure_zone from "Basic_Carrier_Record"."MASTER_Airports" a where a."Airport_IATA"=departure_airport and a."Active";
  if not found then raise exception 'Select a valid departure airport' using errcode='23503';end if;
  select a."IANA_Time_Zone" into arrival_zone from "Basic_Carrier_Record"."MASTER_Airports" a where a."Airport_IATA"=arrival_airport and a."Active";
  if not found then raise exception 'Select a valid arrival airport' using errcode='23503';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=aircraft_type and a."Aircraft_Series_Subtype"=aircraft_subtype)
    then raise exception 'Select an aircraft configured for this carrier' using errcode='23503';end if;
  if aircraft_configuration is not null and not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=aircraft_type and c."Aircraft_Series_Subtype"=aircraft_subtype and btrim(c."Configuration_Code")=aircraft_configuration)
    then raise exception 'Select a valid aircraft configuration' using errcode='23503';end if;
  if aircraft_registration is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=aircraft_type and f."Aircraft_Series_Subtype"=aircraft_subtype and f."E1_2_Registration_Reference" and btrim(f."Aircraft_Registration")=aircraft_registration)
    then raise exception 'Select a valid aircraft registration' using errcode='23503';end if;

  select min(btrim(c."Crew_Code_ID")) into crew_code from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=aircraft_type and c."Aircraft_Series_Subtype"=aircraft_subtype
    having count(distinct btrim(c."Crew_Code_ID"))=1;
  select min(btrim(c."Pantry_Code_ID")) into pantry_code from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=aircraft_type and c."Aircraft_Series_Subtype"=aircraft_subtype
    having count(distinct btrim(c."Pantry_Code_ID"))=1;

  departure_local:=service_date+departure_time;
  arrival_local:=service_date+arrival_day+arrival_time;
  if arrival_local<=departure_local then raise exception 'Arrival must be after departure' using errcode='22023';end if;
  itinerary:=jsonb_build_object(
    'key',concat_ws('|','AD_HOC',p_iata,service_date::text,flight_number,operational_suffix,departure_airport,arrival_airport),
    'route',departure_airport||' → '||arrival_airport,
    'legs',jsonb_build_array(jsonb_build_object(
      'scheduleLegId',null,'legSequence',1,'departureAirport',departure_airport,'arrivalAirport',arrival_airport,
      'departureTime',to_char(departure_time,'HH24:MI'),'arrivalTime',to_char(arrival_time,'HH24:MI'),
      'arrivalDayOffset',arrival_day,'aircraftType',aircraft_type,'aircraftSubtype',aircraft_subtype,
      'aircraftConfiguration',aircraft_configuration,'current',true
    ))
  );

  insert into "Basic_Carrier_Record"."Operational_Flights"(
    "Carrier_IATA","Service_Date","Source_Type","Airline_Designator","Flight_Number","Operational_Suffix",
    "Itinerary_Variation_Identifier","Leg_Sequence_Number","Itinerary_Key","Itinerary_Snapshot","Service_Type",
    "Departure_Airport_IATA","Arrival_Airport_IATA","Scheduled_Departure_Local","Scheduled_Arrival_Local",
    "Estimated_Departure_Local","Estimated_Arrival_Local","Departure_UTC_Offset_Minutes","Arrival_UTC_Offset_Minutes",
    "Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Configuration","Aircraft_Registration",
    "Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Baggage_Weight_Basis","Remarks","Schedule_Snapshot"
  ) values(
    p_iata,service_date,'AD_HOC',p_iata,flight_number,operational_suffix,'ADHOC',1,itinerary->>'key',itinerary,service_type,
    departure_airport,arrival_airport,departure_local,arrival_local,departure_local,arrival_local,
    private.local_utc_offset_minutes(departure_local,departure_zone),private.local_utc_offset_minutes(arrival_local,arrival_zone),
    aircraft_type,aircraft_subtype,aircraft_configuration,aircraft_registration,crew_code,pantry_code,'STANDARD','STANDARD',remarks,
    jsonb_build_object('source','AD_HOC','departureTimeZone',departure_zone,'arrivalTimeZone',arrival_zone)
  ) returning "Operational_Flight_ID" into operational_id;
  return operational_id;
exception when unique_violation then
  raise exception 'This ad-hoc flight already exists on the selected date' using errcode='23505';
end;
$$;

revoke all on function "Basic_Carrier_Record".create_ad_hoc_operational_flight(text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".create_ad_hoc_operational_flight(text,jsonb) to authenticated;

create or replace function "Basic_Carrier_Record".get_daily_load_control_board(
  p_iata text,
  p_service_date date,
  p_airport_iata text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  airport text:=nullif(upper(btrim(p_airport_iata)),'');
  can_operate boolean;
  flights jsonb;
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not(
    private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW')
    or private.has_global_permission('LOAD_CONTROL_VIEW')
  ) then raise exception 'Load Control access denied' using errcode='42501';end if;
  if p_service_date is null or airport is not null and airport!~'^[A-Z]{3}$'
    then raise exception 'Invalid Daily Load Control request' using errcode='22023';end if;
  can_operate:=private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE');

  with scheduled as(
    select l.*,i."Original_File_Name",i."Source_Format",
      p."Schedule_Leg_ID" parameter_leg_id,p."Aircraft_Series_Subtype" parameter_subtype,
      btrim(p."Crew_Code_ID") parameter_crew,btrim(p."Pantry_Code_ID") parameter_pantry,
      p."Passenger_Weight_Basis" parameter_passenger_basis,p."Baggage_Weight_Basis" parameter_baggage_basis,
      private.operational_itinerary_snapshot(l."Schedule_Leg_ID",p_service_date) itinerary,
      f."Operational_Flight_ID",f."Status" operational_status,f."Aircraft_Registration",f."Aircraft_Series_Subtype" operational_subtype,
      f."Crew_Code_ID" operational_crew,f."Pantry_Code_ID" operational_pantry,f."Itinerary_Snapshot" operational_itinerary,
      f."Source_Type" operational_source,f."Updated_At"
    from "Basic_Carrier_Record"."Flight_Schedule_Imports" i
    join "Basic_Carrier_Record"."Scheduled_Flight_Legs" l on l."Import_ID"=i."Import_ID" and l."Carrier_IATA"=i."Carrier_IATA"
    left join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p on p."Schedule_Leg_ID"=l."Schedule_Leg_ID"
    left join "Basic_Carrier_Record"."Operational_Flights" f on f."Schedule_Leg_ID"=l."Schedule_Leg_ID" and f."Service_Date"=p_service_date
    where i."Carrier_IATA"=p_iata and i."Status"='PUBLISHED'
      and p_service_date between l."Period_Start_Date" and l."Period_End_Date"
      and get_bit(l."Operating_Days",extract(isodow from p_service_date)::integer-1)=1
      and (airport is null or airport in(l."Departure_Airport_IATA",l."Arrival_Airport_IATA"))
  ), board_rows as(
    select
      s."Operational_Flight_ID",s."Schedule_Leg_ID",'SCHEDULED'::text source_type,
      coalesce(s.operational_status,'SCHEDULED') status,s."Airline_Designator",s."Flight_Number",s."Operational_Suffix",
      s."Leg_Sequence_Number",btrim(s."Departure_Airport_IATA") departure_airport,btrim(s."Arrival_Airport_IATA") arrival_airport,
      p_service_date+s."Departure_Time_Local" departure_local,p_service_date+s."Arrival_Day_Offset"+s."Arrival_Time_Local" arrival_local,
      s."Aircraft_Type_IATA" aircraft_type,coalesce(s.operational_subtype,s.parameter_subtype,s."Aircraft_Series_Subtype") aircraft_subtype,
      s."Aircraft_Configuration" aircraft_configuration,s."Aircraft_Registration" aircraft_registration,
      coalesce(s.operational_crew,s.parameter_crew) crew_code,coalesce(s.operational_pantry,s.parameter_pantry) pantry_code,
      s.parameter_passenger_basis passenger_basis,s.parameter_baggage_basis baggage_basis,
      coalesce(s.operational_itinerary,s.itinerary) itinerary,s.parameter_leg_id is not null ready,
      s."Original_File_Name" schedule_name,s."Updated_At"
    from scheduled s
    union all
    select
      f."Operational_Flight_ID",null::uuid,'AD_HOC',f."Status",f."Airline_Designator",f."Flight_Number",f."Operational_Suffix",
      f."Leg_Sequence_Number",btrim(f."Departure_Airport_IATA"),btrim(f."Arrival_Airport_IATA"),
      f."Scheduled_Departure_Local",f."Scheduled_Arrival_Local",f."Aircraft_Type_IATA",f."Aircraft_Series_Subtype",
      f."Aircraft_Configuration",f."Aircraft_Registration",f."Crew_Code_ID",f."Pantry_Code_ID",
      f."Passenger_Weight_Basis",f."Baggage_Weight_Basis",f."Itinerary_Snapshot",
      f."Crew_Code_ID" is not null and f."Pantry_Code_ID" is not null,'Ad-hoc flight'::text,f."Updated_At"
    from "Basic_Carrier_Record"."Operational_Flights" f
    where f."Carrier_IATA"=p_iata and f."Service_Date"=p_service_date and f."Source_Type"='AD_HOC'
      and (airport is null or airport in(f."Departure_Airport_IATA",f."Arrival_Airport_IATA"))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'operationalFlightId',r."Operational_Flight_ID",'scheduleLegId',r."Schedule_Leg_ID",'sourceType',r.source_type,
    'status',r.status,'flightNumber',r."Flight_Number",'airlineDesignator',r."Airline_Designator",
    'operationalSuffix',r."Operational_Suffix",'legSequence',r."Leg_Sequence_Number",
    'departureAirport',r.departure_airport,'arrivalAirport',r.arrival_airport,
    'departureLocal',r.departure_local,'arrivalLocal',r.arrival_local,'aircraftType',r.aircraft_type,
    'aircraftSubtype',r.aircraft_subtype,'aircraftConfiguration',r.aircraft_configuration,
    'aircraftRegistration',r.aircraft_registration,'crewCode',r.crew_code,'pantryCode',r.pantry_code,
    'passengerWeightBasis',r.passenger_basis,'baggageWeightBasis',r.baggage_basis,'itinerary',r.itinerary,
    'ready',r.ready,'canStart',can_operate and r."Operational_Flight_ID" is null and r.ready,
    'scheduleName',nullif(r.schedule_name,''),'updatedAt',r."Updated_At"
  ) order by r.departure_local,r."Airline_Designator",r."Flight_Number",r."Leg_Sequence_Number"),'[]'::jsonb)
  into flights from board_rows r;

  return jsonb_build_object(
    'serviceDate',p_service_date,'airport',airport,'canOperate',can_operate,'flights',flights,
    'airports',coalesce((select jsonb_agg(jsonb_build_object('iata',btrim(a."Airport_IATA"),'name',a."Airport_Name") order by a."Airport_IATA") from "Basic_Carrier_Record"."MASTER_Airports" a where a."Active"),'[]'::jsonb),
    'aircraft',coalesce((select jsonb_agg(jsonb_build_object('typeCode',a."Aircraft_Type_IATA",'subtype',a."Aircraft_Series_Subtype",'name',btrim(a."Aircraft_Type")) order by a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype") from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata),'[]'::jsonb),
    'serviceTypes',coalesce((select jsonb_agg(jsonb_build_object('code',s."Service_Type_Code",'name',s."Service_Type_Name") order by s."Service_Type_Code") from "Basic_Carrier_Record"."MASTER_Flight_Service_Types" s where s."Active"),'[]'::jsonb)
  );
end;
$$;

revoke all on function "Basic_Carrier_Record".get_daily_load_control_board(text,date,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_daily_load_control_board(text,date,text) to authenticated;

create or replace function "Basic_Carrier_Record".get_operational_flight(
  p_iata text,
  p_operational_flight_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare result jsonb;
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not(
    private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW')
    or private.has_global_permission('LOAD_CONTROL_VIEW')
  ) then raise exception 'Load Control access denied' using errcode='42501';end if;

  select jsonb_build_object(
    'operationalFlightId',f."Operational_Flight_ID",'sourceType',f."Source_Type",'serviceDate',f."Service_Date",
    'airlineDesignator',f."Airline_Designator",'flightNumber',f."Flight_Number",'operationalSuffix',f."Operational_Suffix",
    'status',f."Status",'legSequence',f."Leg_Sequence_Number",'departureAirport',btrim(f."Departure_Airport_IATA"),
    'arrivalAirport',btrim(f."Arrival_Airport_IATA"),'departureLocal',f."Scheduled_Departure_Local",
    'arrivalLocal',f."Scheduled_Arrival_Local",'departureUtcOffsetMinutes',f."Departure_UTC_Offset_Minutes",
    'arrivalUtcOffsetMinutes',f."Arrival_UTC_Offset_Minutes",'aircraftType',f."Aircraft_Type_IATA",
    'aircraftSubtype',f."Aircraft_Series_Subtype",'aircraftConfiguration',f."Aircraft_Configuration",
    'aircraftRegistration',f."Aircraft_Registration",'crewCode',f."Crew_Code_ID",'pantryCode',f."Pantry_Code_ID",
    'passengerWeightBasis',f."Passenger_Weight_Basis",'baggageWeightBasis',f."Baggage_Weight_Basis",
    'itinerary',f."Itinerary_Snapshot",'remarks',f."Remarks",'version',f."Version",'startedAt',f."Started_At",
    'updatedAt',f."Updated_At",'events',coalesce((select jsonb_agg(jsonb_build_object(
      'eventId',e."Event_ID",'eventType',e."Event_Type",'previousStatus',e."Previous_Status",
      'newStatus',e."New_Status",'occurredAt',e."Occurred_At"
    ) order by e."Occurred_At" desc,e."Event_ID" desc) from "Basic_Carrier_Record"."Operational_Flight_Events" e where e."Operational_Flight_ID"=f."Operational_Flight_ID"),'[]'::jsonb)
  ) into result
  from "Basic_Carrier_Record"."Operational_Flights" f
  where f."Carrier_IATA"=p_iata and f."Operational_Flight_ID"=p_operational_flight_id;
  if result is null then raise exception 'Operational flight not found' using errcode='P0002';end if;
  return result;
end;
$$;

revoke all on function "Basic_Carrier_Record".get_operational_flight(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_flight(text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
