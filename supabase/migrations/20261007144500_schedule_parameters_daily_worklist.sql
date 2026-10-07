begin;

create function private.copy_schedule_parameters_to_new_publication()
returns trigger language plpgsql security definer set search_path='' as $$
declare previous_id uuid;
begin
 if new."Status"<>'PUBLISHED' or old."Status"='PUBLISHED' then return new;end if;
 select "Import_ID" into previous_id from "Basic_Carrier_Record"."Flight_Schedule_Imports"
 where "Carrier_IATA"=new."Carrier_IATA" and "Status"='SUPERSEDED' and "Import_ID"<>new."Import_ID"
 order by "Superseded_At" desc nulls last limit 1;
 if previous_id is null then return new;end if;
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"(
  "Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID",
  "Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Updated_By","Updated_At"
 )
 select target."Schedule_Leg_ID",new."Carrier_IATA",p."Aircraft_Series_Subtype",p."Crew_Code_ID",p."Pantry_Code_ID",
  p."Passenger_Weight_Basis",p."Passenger_Flight_Variation",p."Baggage_Weight_Basis",p."Baggage_Flight_Variation",p."Remarks",new."Published_By",now()
 from "Basic_Carrier_Record"."Scheduled_Flight_Legs" source
 join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p on p."Schedule_Leg_ID"=source."Schedule_Leg_ID"
 join "Basic_Carrier_Record"."Scheduled_Flight_Legs" target on target."Import_ID"=new."Import_ID"
  and target."Airline_Designator"=source."Airline_Designator" and target."Flight_Number"=source."Flight_Number"
  and target."Operational_Suffix"=source."Operational_Suffix" and target."Itinerary_Variation_Identifier"=source."Itinerary_Variation_Identifier"
  and target."Leg_Sequence_Number"=source."Leg_Sequence_Number" and target."Departure_Airport_IATA"=source."Departure_Airport_IATA"
  and target."Arrival_Airport_IATA"=source."Arrival_Airport_IATA" and target."Aircraft_Type_IATA" is not distinct from source."Aircraft_Type_IATA"
 where source."Import_ID"=previous_id
 on conflict("Schedule_Leg_ID") do nothing;
 return new;
end $$;
revoke all on function private.copy_schedule_parameters_to_new_publication() from public,anon,authenticated;
create trigger "copy_schedule_parameters_to_new_publication"
after update of "Status" on "Basic_Carrier_Record"."Flight_Schedule_Imports"
for each row when(new."Status"='PUBLISHED' and old."Status" is distinct from new."Status")
execute function private.copy_schedule_parameters_to_new_publication();

create or replace function "Basic_Carrier_Record".get_daily_flight_schedule(
  p_iata text,p_service_date date,p_airport_iata text default null
)
returns table(
  "Schedule_Leg_ID" uuid,"Import_ID" uuid,"Carrier_IATA" varchar,"Service_Date" date,"Airline_Designator" varchar,
  "Flight_Number" varchar,"Operational_Suffix" varchar,"Itinerary_Variation_Identifier" varchar,"Leg_Sequence_Number" smallint,
  "Service_Type" varchar,"Departure_Airport_IATA" char(3),"Arrival_Airport_IATA" char(3),"Departure_Local" timestamp without time zone,
  "Arrival_Local" timestamp without time zone,"Departure_UTC_Offset_Minutes" smallint,"Arrival_UTC_Offset_Minutes" smallint,
  "Departure_Terminal" varchar,"Arrival_Terminal" varchar,"Aircraft_Type_IATA" varchar,"Aircraft_Configuration" varchar,"Additional_Data" jsonb
)
language plpgsql stable security invoker set search_path='' as $$
declare airport text:=nullif(upper(btrim(p_airport_iata)),'');
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW')) then raise exception 'Flight schedule access denied' using errcode='42501';end if;
 if p_service_date is null or (airport is not null and airport!~'^[A-Z0-9]{3}$') then raise exception 'Invalid daily schedule request' using errcode='22023';end if;
 return query select leg."Schedule_Leg_ID",leg."Import_ID",leg."Carrier_IATA",p_service_date,leg."Airline_Designator",leg."Flight_Number",leg."Operational_Suffix",leg."Itinerary_Variation_Identifier",leg."Leg_Sequence_Number",leg."Service_Type",leg."Departure_Airport_IATA",leg."Arrival_Airport_IATA",p_service_date+leg."Departure_Time_Local",p_service_date+leg."Arrival_Day_Offset"+leg."Arrival_Time_Local",leg."Departure_UTC_Offset_Minutes",leg."Arrival_UTC_Offset_Minutes",leg."Departure_Terminal",leg."Arrival_Terminal",leg."Aircraft_Type_IATA",leg."Aircraft_Configuration",
  leg."Additional_Data"||jsonb_build_object('loadControlReady',params."Schedule_Leg_ID" is not null,'loadControlParameters',case when params."Schedule_Leg_ID" is null then null else jsonb_build_object('aircraftSubtype',params."Aircraft_Series_Subtype",'crewCode',btrim(params."Crew_Code_ID"),'pantryCode',btrim(params."Pantry_Code_ID"),'passengerWeightBasis',params."Passenger_Weight_Basis",'passengerVariation',params."Passenger_Flight_Variation",'baggageWeightBasis',params."Baggage_Weight_Basis",'baggageVariation',params."Baggage_Flight_Variation",'remarks',params."Remarks") end)
 from "Basic_Carrier_Record"."Flight_Schedule_Imports" imp join "Basic_Carrier_Record"."Scheduled_Flight_Legs" leg on leg."Import_ID"=imp."Import_ID" and leg."Carrier_IATA"=imp."Carrier_IATA" left join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" params on params."Schedule_Leg_ID"=leg."Schedule_Leg_ID"
 where imp."Carrier_IATA"=p_iata and imp."Status"='PUBLISHED' and p_service_date between leg."Period_Start_Date" and leg."Period_End_Date" and get_bit(leg."Operating_Days",extract(isodow from p_service_date)::integer-1)=1 and(airport is null or airport in(leg."Departure_Airport_IATA",leg."Arrival_Airport_IATA"))
 order by leg."Departure_Time_Local",leg."Airline_Designator",leg."Flight_Number",leg."Leg_Sequence_Number";
end $$;

notify pgrst,'reload schema';
commit;
