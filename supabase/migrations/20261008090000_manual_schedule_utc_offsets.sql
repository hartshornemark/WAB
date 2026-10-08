begin;

create or replace function private.local_utc_offset_minutes(
  p_local_timestamp timestamp without time zone,
  p_iana_time_zone text
)
returns smallint
language sql
stable
strict
set search_path = ''
as $$
  select round(
    extract(
      epoch from (
        p_local_timestamp
        - ((p_local_timestamp at time zone p_iana_time_zone) at time zone 'UTC')
      )
    ) / 60
  )::smallint;
$$;

revoke all on function private.local_utc_offset_minutes(timestamp without time zone, text)
  from public, anon;
grant execute on function private.local_utc_offset_minutes(timestamp without time zone, text)
  to authenticated;

create or replace function private.set_manual_schedule_utc_offsets()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_format text;
  departure_zone text;
  arrival_zone text;
begin
  select i."Source_Format"
    into source_format
  from "Basic_Carrier_Record"."Flight_Schedule_Imports" i
  where i."Import_ID" = new."Import_ID";

  if source_format <> 'MANUAL' then
    return new;
  end if;

  select a."IANA_Time_Zone"
    into departure_zone
  from "Basic_Carrier_Record"."MASTER_Airports" a
  where a."Airport_IATA" = new."Departure_Airport_IATA";

  select a."IANA_Time_Zone"
    into arrival_zone
  from "Basic_Carrier_Record"."MASTER_Airports" a
  where a."Airport_IATA" = new."Arrival_Airport_IATA";

  if departure_zone is not null then
    new."Departure_UTC_Offset_Minutes" := private.local_utc_offset_minutes(
      new."Period_Start_Date" + new."Departure_Time_Local",
      departure_zone
    );
  end if;

  if arrival_zone is not null then
    new."Arrival_UTC_Offset_Minutes" := private.local_utc_offset_minutes(
      new."Period_Start_Date" + new."Arrival_Day_Offset" + new."Arrival_Time_Local",
      arrival_zone
    );
  end if;

  return new;
end;
$$;

revoke all on function private.set_manual_schedule_utc_offsets()
  from public, anon, authenticated;

drop trigger if exists "set_manual_schedule_utc_offsets"
  on "Basic_Carrier_Record"."Scheduled_Flight_Legs";

create trigger "set_manual_schedule_utc_offsets"
before insert or update of
  "Import_ID",
  "Period_Start_Date",
  "Departure_Airport_IATA",
  "Arrival_Airport_IATA",
  "Departure_Time_Local",
  "Arrival_Time_Local",
  "Arrival_Day_Offset"
on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
for each row
execute function private.set_manual_schedule_utc_offsets();

-- This migration is the only controlled write to historical published rows.
-- The immutability guard is restored before the transaction commits.
alter table "Basic_Carrier_Record"."Scheduled_Flight_Legs"
  disable trigger "guard_published_schedule_legs";

update "Basic_Carrier_Record"."Scheduled_Flight_Legs" leg
set
  "Departure_UTC_Offset_Minutes" = private.local_utc_offset_minutes(
    leg."Period_Start_Date" + leg."Departure_Time_Local",
    departure_airport."IANA_Time_Zone"
  ),
  "Arrival_UTC_Offset_Minutes" = private.local_utc_offset_minutes(
    leg."Period_Start_Date" + leg."Arrival_Day_Offset" + leg."Arrival_Time_Local",
    arrival_airport."IANA_Time_Zone"
  )
from
  "Basic_Carrier_Record"."Flight_Schedule_Imports" schedule_import,
  "Basic_Carrier_Record"."MASTER_Airports" departure_airport,
  "Basic_Carrier_Record"."MASTER_Airports" arrival_airport
where schedule_import."Import_ID" = leg."Import_ID"
  and schedule_import."Source_Format" = 'MANUAL'
  and departure_airport."Airport_IATA" = leg."Departure_Airport_IATA"
  and arrival_airport."Airport_IATA" = leg."Arrival_Airport_IATA";

alter table "Basic_Carrier_Record"."Scheduled_Flight_Legs"
  enable trigger "guard_published_schedule_legs";

create or replace function "Basic_Carrier_Record".get_daily_flight_schedule(
  p_iata text,
  p_service_date date,
  p_airport_iata text default null
)
returns table(
  "Schedule_Leg_ID" uuid,
  "Import_ID" uuid,
  "Carrier_IATA" varchar,
  "Service_Date" date,
  "Airline_Designator" varchar,
  "Flight_Number" varchar,
  "Operational_Suffix" varchar,
  "Itinerary_Variation_Identifier" varchar,
  "Leg_Sequence_Number" smallint,
  "Service_Type" varchar,
  "Departure_Airport_IATA" char(3),
  "Arrival_Airport_IATA" char(3),
  "Departure_Local" timestamp without time zone,
  "Arrival_Local" timestamp without time zone,
  "Departure_UTC_Offset_Minutes" smallint,
  "Arrival_UTC_Offset_Minutes" smallint,
  "Departure_Terminal" varchar,
  "Arrival_Terminal" varchar,
  "Aircraft_Type_IATA" varchar,
  "Aircraft_Configuration" varchar,
  "Additional_Data" jsonb
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  airport text := nullif(upper(btrim(p_airport_iata)), '');
begin
  p_iata := upper(btrim(p_iata));

  if (select auth.uid()) is null
    or not (
      private.has_carrier_permission(p_iata, 'FLIGHT_SCHEDULE_VIEW')
      or private.has_global_permission('FLIGHT_SCHEDULE_VIEW')
    ) then
    raise exception 'Flight schedule access denied' using errcode = '42501';
  end if;

  if p_service_date is null
    or (airport is not null and airport !~ '^[A-Z0-9]{3}$') then
    raise exception 'Invalid daily schedule request' using errcode = '22023';
  end if;

  return query
  select
    leg."Schedule_Leg_ID",
    leg."Import_ID",
    leg."Carrier_IATA",
    p_service_date,
    leg."Airline_Designator",
    leg."Flight_Number",
    leg."Operational_Suffix",
    leg."Itinerary_Variation_Identifier",
    leg."Leg_Sequence_Number",
    leg."Service_Type",
    leg."Departure_Airport_IATA",
    leg."Arrival_Airport_IATA",
    p_service_date + leg."Departure_Time_Local",
    p_service_date + leg."Arrival_Day_Offset" + leg."Arrival_Time_Local",
    case
      when schedule_import."Source_Format" = 'MANUAL'
        and nullif(leg."Additional_Data" ->> 'departureTimeZone', '') is not null
      then private.local_utc_offset_minutes(
        p_service_date + leg."Departure_Time_Local",
        leg."Additional_Data" ->> 'departureTimeZone'
      )
      else leg."Departure_UTC_Offset_Minutes"
    end,
    case
      when schedule_import."Source_Format" = 'MANUAL'
        and nullif(leg."Additional_Data" ->> 'arrivalTimeZone', '') is not null
      then private.local_utc_offset_minutes(
        p_service_date + leg."Arrival_Day_Offset" + leg."Arrival_Time_Local",
        leg."Additional_Data" ->> 'arrivalTimeZone'
      )
      else leg."Arrival_UTC_Offset_Minutes"
    end,
    leg."Departure_Terminal",
    leg."Arrival_Terminal",
    leg."Aircraft_Type_IATA",
    leg."Aircraft_Configuration",
    leg."Additional_Data" || jsonb_build_object(
      'loadControlReady', parameters."Schedule_Leg_ID" is not null,
      'loadControlParameters', case
        when parameters."Schedule_Leg_ID" is null then null
        else jsonb_build_object(
          'aircraftSubtype', parameters."Aircraft_Series_Subtype",
          'crewCode', btrim(parameters."Crew_Code_ID"),
          'pantryCode', btrim(parameters."Pantry_Code_ID"),
          'passengerWeightBasis', parameters."Passenger_Weight_Basis",
          'passengerVariation', parameters."Passenger_Flight_Variation",
          'baggageWeightBasis', parameters."Baggage_Weight_Basis",
          'baggageVariation', parameters."Baggage_Flight_Variation",
          'remarks', parameters."Remarks"
        )
      end
    )
  from "Basic_Carrier_Record"."Flight_Schedule_Imports" schedule_import
  join "Basic_Carrier_Record"."Scheduled_Flight_Legs" leg
    on leg."Import_ID" = schedule_import."Import_ID"
    and leg."Carrier_IATA" = schedule_import."Carrier_IATA"
  left join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" parameters
    on parameters."Schedule_Leg_ID" = leg."Schedule_Leg_ID"
  where schedule_import."Carrier_IATA" = p_iata
    and schedule_import."Status" = 'PUBLISHED'
    and p_service_date between leg."Period_Start_Date" and leg."Period_End_Date"
    and get_bit(
      leg."Operating_Days",
      extract(isodow from p_service_date)::integer - 1
    ) = 1
    and (
      airport is null
      or airport in (leg."Departure_Airport_IATA", leg."Arrival_Airport_IATA")
    )
  order by
    leg."Departure_Time_Local",
    leg."Airline_Designator",
    leg."Flight_Number",
    leg."Leg_Sequence_Number";
end;
$$;

notify pgrst, 'reload schema';

commit;
