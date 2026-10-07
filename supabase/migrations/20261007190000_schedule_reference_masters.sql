begin;

create table "Basic_Carrier_Record"."MASTER_Flight_Service_Types"(
  "Service_Type_Code" char(1) primary key check(btrim("Service_Type_Code") ~ '^[A-Z0-9]$'),
  "Service_Type_Name" varchar(100) not null check(char_length(btrim("Service_Type_Name")) between 1 and 100),
  "Description" text,
  "Active" boolean not null default true,
  "Updated_At" timestamptz not null default now()
);

create table "Basic_Carrier_Record"."MASTER_Airports"(
  "Airport_IATA" char(3) primary key check(btrim("Airport_IATA") ~ '^[A-Z]{3}$'),
  "Airport_ICAO" char(4) unique check("Airport_ICAO" is null or btrim("Airport_ICAO") ~ '^[A-Z0-9]{4}$'),
  "Airport_Name" varchar(160) not null check(char_length(btrim("Airport_Name")) between 1 and 160),
  "City_Name" varchar(120),
  "Country_Code" char(2) check("Country_Code" is null or btrim("Country_Code") ~ '^[A-Z]{2}$'),
  "IANA_Time_Zone" text not null,
  "Active" boolean not null default true,
  "Updated_At" timestamptz not null default now()
);

create function private.validate_airport_iana_time_zone()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=new."IANA_Time_Zone") then
    raise exception 'Enter a valid IANA time-zone identifier' using errcode='22023';
  end if;
  return new;
end $$;

create trigger "master_airports_validate_time_zone"
before insert or update of "IANA_Time_Zone" on "Basic_Carrier_Record"."MASTER_Airports"
for each row execute function private.validate_airport_iana_time_zone();

alter table "Basic_Carrier_Record"."MASTER_Flight_Service_Types" enable row level security;
alter table "Basic_Carrier_Record"."MASTER_Airports" enable row level security;
revoke all on "Basic_Carrier_Record"."MASTER_Flight_Service_Types" from public,anon,authenticated;
revoke all on "Basic_Carrier_Record"."MASTER_Airports" from public,anon,authenticated;
grant select on "Basic_Carrier_Record"."MASTER_Flight_Service_Types" to authenticated;
grant select on "Basic_Carrier_Record"."MASTER_Airports" to authenticated;
create policy "master_flight_service_types_select" on "Basic_Carrier_Record"."MASTER_Flight_Service_Types"
for select to authenticated using((select auth.uid()) is not null);
create policy "master_airports_select" on "Basic_Carrier_Record"."MASTER_Airports"
for select to authenticated using((select auth.uid()) is not null);

alter table "Basic_Carrier_Record"."Scheduled_Flight_Legs"
add column "Aircraft_Series_Subtype" varchar(4);

create or replace function "Basic_Carrier_Record".get_flight_schedule_workspace(p_iata text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare can_view boolean;can_configure boolean;published_id uuid;payload jsonb;
begin
 p_iata:=upper(btrim(p_iata));
 can_view:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW'));
 can_configure:=private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE');
 if not can_view then raise exception 'Flight schedule access denied' using errcode='42501';end if;
 select "Import_ID" into published_id from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=p_iata and "Status"='PUBLISHED';
 select jsonb_build_object(
  'canView',can_view,'canConfigure',can_configure,'publishedImportId',published_id,
  'legs',coalesce((select jsonb_agg(jsonb_build_object(
    'scheduleLegId',l."Schedule_Leg_ID",'flightNumber',l."Flight_Number",'operationalSuffix',l."Operational_Suffix",
    'itineraryVariation',l."Itinerary_Variation_Identifier",'legSequence',l."Leg_Sequence_Number",'serviceType',l."Service_Type",
    'periodStart',l."Period_Start_Date",'periodEnd',l."Period_End_Date",'operatingDays',l."Operating_Days"::text,
    'departureAirport',btrim(l."Departure_Airport_IATA"),'arrivalAirport',btrim(l."Arrival_Airport_IATA"),
    'departureTime',to_char(l."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(l."Arrival_Time_Local",'HH24:MI'),'arrivalDayOffset',l."Arrival_Day_Offset",
    'aircraftType',l."Aircraft_Type_IATA",'aircraftSubtype',l."Aircraft_Series_Subtype",'aircraftConfiguration',l."Aircraft_Configuration",
    'parameters',case when p."Schedule_Leg_ID" is null then null else jsonb_build_object(
      'aircraftSubtype',p."Aircraft_Series_Subtype",'crewCode',btrim(p."Crew_Code_ID"),'pantryCode',btrim(p."Pantry_Code_ID"),
      'passengerWeightBasis',p."Passenger_Weight_Basis",'passengerVariation',p."Passenger_Flight_Variation",
      'baggageWeightBasis',p."Baggage_Weight_Basis",'baggageVariation',p."Baggage_Flight_Variation",'remarks',coalesce(p."Remarks",'')) end
  ) order by l."Flight_Number",l."Itinerary_Variation_Identifier",l."Leg_Sequence_Number",l."Period_Start_Date")
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l left join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p using("Schedule_Leg_ID") where l."Import_ID"=published_id),'[]'::jsonb),
  'serviceTypes',coalesce((select jsonb_agg(jsonb_build_object('code',btrim(s."Service_Type_Code"),'name',btrim(s."Service_Type_Name"),'description',coalesce(s."Description",'')) order by s."Service_Type_Code") from "Basic_Carrier_Record"."MASTER_Flight_Service_Types" s where s."Active"),'[]'::jsonb),
  'airports',coalesce((select jsonb_agg(jsonb_build_object('iata',btrim(a."Airport_IATA"),'icao',nullif(btrim(a."Airport_ICAO"),''),'name',btrim(a."Airport_Name"),'city',coalesce(btrim(a."City_Name"),''),'countryCode',nullif(btrim(a."Country_Code"),''),'timeZone',a."IANA_Time_Zone") order by a."Airport_IATA") from "Basic_Carrier_Record"."MASTER_Airports" a where a."Active"),'[]'::jsonb),
  'aircraft',coalesce((select jsonb_agg(jsonb_build_object('typeCode',a."Aircraft_Type_IATA",'subtype',a."Aircraft_Series_Subtype",'name',btrim(a."Aircraft_Type")) order by a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype") from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata),'[]'::jsonb),
  'aircraftConfigurations',coalesce((select jsonb_agg(jsonb_build_object('typeCode',x."Aircraft_Type_IATA",'subtype',x."Aircraft_Series_Subtype",'code',x."Configuration_Code",'description',x."Configuration_Code_Description") order by x."Aircraft_Type_IATA",x."Aircraft_Series_Subtype",x."Configuration_Code") from(select "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Configuration_Code") "Configuration_Code",min(btrim("Configuration_Code_Description")) "Configuration_Code_Description" from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata group by "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Configuration_Code"))x),'[]'::jsonb),
  'crewCodes',coalesce((select jsonb_agg(jsonb_build_object('typeCode',x."Aircraft_Type_IATA",'subtype',x."Aircraft_Series_Subtype",'code',x."Crew_Code_ID") order by x."Aircraft_Type_IATA",x."Aircraft_Series_Subtype",x."Crew_Code_ID") from(select distinct "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Crew_Code_ID") "Crew_Code_ID" from "Basic_Carrier_Record"."Aircraft_Crew_Codes" where "Carrier_IATA"=p_iata)x),'[]'::jsonb),
  'pantryCodes',coalesce((select jsonb_agg(jsonb_build_object('typeCode',x."Aircraft_Type_IATA",'subtype',x."Aircraft_Series_Subtype",'code',x."Pantry_Code_ID") order by x."Aircraft_Type_IATA",x."Aircraft_Series_Subtype",x."Pantry_Code_ID") from(select distinct "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Pantry_Code_ID") "Pantry_Code_ID" from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" where "Carrier_IATA"=p_iata)x),'[]'::jsonb),
  'variations',coalesce((select jsonb_agg(jsonb_build_object('code',"Flight_Type_Variation",'description',"Flight_Type_Variation_Description") order by "Flight_Type_Variation") from "Basic_Carrier_Record"."Carrier_Flight_Variations" where "Carrier_IATA"=p_iata),'[]'::jsonb)
 ) into payload;
 return payload;
end $$;

create or replace function "Basic_Carrier_Record".get_flight_schedule_edition(p_iata text,p_import_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;can_view boolean;can_configure boolean;
begin
 p_iata:=upper(btrim(p_iata));
 can_view:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW'));
 can_configure:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE'));
 if not can_view then raise exception 'Flight schedule access denied' using errcode='42501';end if;
 select * into item from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata;
 if not found then raise exception 'Schedule edition not found' using errcode='P0002';end if;
 return jsonb_build_object(
  'importId',item."Import_ID",'name',item."Original_File_Name",'sourceFormat',item."Source_Format",'status',item."Status",'seasonCode',item."Season_Code",
  'coverageStart',item."Coverage_Start_Date",'coverageEnd',item."Coverage_End_Date",'recordCount',item."Total_Record_Count",'legCount',item."Normalized_Leg_Count",'rejectedCount',item."Rejected_Record_Count",
  'canEdit',can_configure and item."Source_Format"='MANUAL' and item."Status" in('DRAFT','VALIDATED'),'canDelete',can_configure and item."Status"<>'PUBLISHED',
  'legs',coalesce((select jsonb_agg(jsonb_build_object(
    'scheduleLegId',l."Schedule_Leg_ID",'flightNumber',l."Flight_Number",'operationalSuffix',l."Operational_Suffix",'itineraryVariation',l."Itinerary_Variation_Identifier",
    'legSequence',l."Leg_Sequence_Number",'serviceType',l."Service_Type",'periodStart',l."Period_Start_Date",'periodEnd',l."Period_End_Date",'operatingDays',l."Operating_Days"::text,
    'departureAirport',btrim(l."Departure_Airport_IATA"),'arrivalAirport',btrim(l."Arrival_Airport_IATA"),'departureTime',to_char(l."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(l."Arrival_Time_Local",'HH24:MI'),
    'arrivalDayOffset',l."Arrival_Day_Offset",'aircraftType',l."Aircraft_Type_IATA",'aircraftSubtype',l."Aircraft_Series_Subtype",'aircraftConfiguration',l."Aircraft_Configuration"
  ) order by l."Flight_Number",l."Itinerary_Variation_Identifier",l."Leg_Sequence_Number",l."Period_Start_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=item."Import_ID"),'[]'::jsonb)
 );
end $$;

create or replace function "Basic_Carrier_Record".save_manual_schedule_leg(p_iata text,p_import_id uuid,p_schedule_leg_id uuid,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare status text;source_format text;leg_id uuid:=p_schedule_leg_id;line_no integer;airline text;flight text;suffix text;variation text;leg_sequence smallint;service text;period_start date;period_end date;days text;departure text;arrival text;departure_time time;arrival_time time;arrival_day smallint;aircraft_type text;aircraft_subtype text;aircraft_configuration text;departure_zone text;arrival_zone text;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Manual schedule access denied' using errcode='42501';end if;
 select "Status","Source_Format" into status,source_format from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata for update;
 if not found or source_format<>'MANUAL' or status not in('DRAFT','VALIDATED') then raise exception 'Editable manual schedule not found' using errcode='55000';end if;
 airline:=upper(btrim(coalesce(p_values->>'airlineDesignator',p_iata)));flight:=btrim(p_values->>'flightNumber');suffix:=upper(btrim(coalesce(p_values->>'operationalSuffix','')));variation:=upper(btrim(coalesce(p_values->>'itineraryVariation','01')));leg_sequence:=(p_values->>'legSequence')::smallint;service:=upper(btrim(p_values->>'serviceType'));period_start:=(p_values->>'periodStart')::date;period_end:=(p_values->>'periodEnd')::date;days:=p_values->>'operatingDays';departure:=upper(btrim(p_values->>'departureAirport'));arrival:=upper(btrim(p_values->>'arrivalAirport'));departure_time:=(p_values->>'departureTime')::time;arrival_time:=(p_values->>'arrivalTime')::time;arrival_day:=(p_values->>'arrivalDayOffset')::smallint;aircraft_type:=upper(btrim(p_values->>'aircraftType'));aircraft_subtype:=upper(btrim(p_values->>'aircraftSubtype'));aircraft_configuration:=nullif(upper(btrim(p_values->>'aircraftConfiguration')),'');
 if airline<>p_iata or flight!~'^(?:[0-9]{1,4}|[0-9]{1,3}[A-Z])$' or suffix!~'^[A-Z0-9]?$' or variation!~'^[A-Z0-9]{1,8}$' or leg_sequence not between 1 and 99 or period_end<period_start or days!~'^[01]{7}$' or days='0000000' or departure=arrival or arrival_day not between 0 and 2 then raise exception 'Check every manual schedule value' using errcode='22023';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."MASTER_Flight_Service_Types" s where s."Service_Type_Code"=service and s."Active") then raise exception 'Select a valid service type' using errcode='23503';end if;
 select a."IANA_Time_Zone" into departure_zone from "Basic_Carrier_Record"."MASTER_Airports" a where a."Airport_IATA"=departure and a."Active";
 if not found then raise exception 'Select a valid departure airport' using errcode='23503';end if;
 select a."IANA_Time_Zone" into arrival_zone from "Basic_Carrier_Record"."MASTER_Airports" a where a."Airport_IATA"=arrival and a."Active";
 if not found then raise exception 'Select a valid arrival airport' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=aircraft_type and a."Aircraft_Series_Subtype"=aircraft_subtype) then raise exception 'Select an aircraft configured for this carrier' using errcode='23503';end if;
 if aircraft_configuration is not null and not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=aircraft_type and c."Aircraft_Series_Subtype"=aircraft_subtype and btrim(c."Configuration_Code")=aircraft_configuration) then raise exception 'Select a valid aircraft configuration' using errcode='23503';end if;
 if leg_id is null then
  select coalesce(max("Line_Number"),0)+1 into line_no from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" where "Import_ID"=p_import_id;
  insert into "Basic_Carrier_Record"."Flight_Schedule_Import_Records"("Import_ID","Carrier_IATA","Line_Number","Record_Type","Raw_Record","Parse_Status","Parsed_Data") values(p_import_id,p_iata,line_no,'M','MANUAL ENTRY '||line_no,'PARSED',p_values);
  insert into "Basic_Carrier_Record"."Scheduled_Flight_Legs"("Import_ID","Carrier_IATA","Source_Line_Number","Airline_Designator","Flight_Number","Operational_Suffix","Itinerary_Variation_Identifier","Leg_Sequence_Number","Service_Type","Period_Start_Date","Period_End_Date","Operating_Days","Departure_Airport_IATA","Arrival_Airport_IATA","Departure_Time_Local","Arrival_Time_Local","Arrival_Day_Offset","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Configuration","Additional_Data") values(p_import_id,p_iata,line_no,airline,flight,suffix,variation,leg_sequence,service,period_start,period_end,days::bit(7),departure,arrival,departure_time,arrival_time,arrival_day,aircraft_type,aircraft_subtype,aircraft_configuration,jsonb_build_object('source','MANUAL','departureTimeZone',departure_zone,'arrivalTimeZone',arrival_zone)) returning "Schedule_Leg_ID" into leg_id;
 else
  select "Source_Line_Number" into line_no from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Schedule_Leg_ID"=leg_id and "Import_ID"=p_import_id and "Carrier_IATA"=p_iata;
  if not found then raise exception 'Manual schedule leg not found' using errcode='P0002';end if;
  update "Basic_Carrier_Record"."Scheduled_Flight_Legs" set "Airline_Designator"=airline,"Flight_Number"=flight,"Operational_Suffix"=suffix,"Itinerary_Variation_Identifier"=variation,"Leg_Sequence_Number"=leg_sequence,"Service_Type"=service,"Period_Start_Date"=period_start,"Period_End_Date"=period_end,"Operating_Days"=days::bit(7),"Departure_Airport_IATA"=departure,"Arrival_Airport_IATA"=arrival,"Departure_Time_Local"=departure_time,"Arrival_Time_Local"=arrival_time,"Arrival_Day_Offset"=arrival_day,"Aircraft_Type_IATA"=aircraft_type,"Aircraft_Series_Subtype"=aircraft_subtype,"Aircraft_Configuration"=aircraft_configuration,"Additional_Data"=coalesce("Additional_Data",'{}'::jsonb)||jsonb_build_object('source','MANUAL','departureTimeZone',departure_zone,'arrivalTimeZone',arrival_zone) where "Schedule_Leg_ID"=leg_id;
  update "Basic_Carrier_Record"."Flight_Schedule_Import_Records" set "Parsed_Data"=p_values where "Import_ID"=p_import_id and "Line_Number"=line_no;
 end if;
 update "Basic_Carrier_Record"."Flight_Schedule_Imports" i set "Status"='VALIDATED',"Validated_At"=now(),"Total_Record_Count"=(select count(*) from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" r where r."Import_ID"=p_import_id),"Accepted_Record_Count"=(select count(*) from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" r where r."Import_ID"=p_import_id),"Rejected_Record_Count"=0,"Normalized_Leg_Count"=(select count(*) from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),"Coverage_Start_Date"=(select min("Period_Start_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),"Coverage_End_Date"=(select max("Period_End_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),"Validation_Summary"=jsonb_build_object('valid',true,'source','MANUAL') where i."Import_ID"=p_import_id;
 return jsonb_build_object('importId',p_import_id,'scheduleLegId',leg_id,'status','VALIDATED');
end $$;

notify pgrst,'reload schema';
commit;
