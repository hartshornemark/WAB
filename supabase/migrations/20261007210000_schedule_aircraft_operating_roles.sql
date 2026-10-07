begin;

-- Expose the C1 aircraft operating role so schedule parameters can omit
-- passenger-only choices for freighter aircraft.
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
  'legs',coalesce((select jsonb_agg(jsonb_build_object('scheduleLegId',l."Schedule_Leg_ID",'flightNumber',l."Flight_Number",'operationalSuffix',l."Operational_Suffix",'itineraryVariation',l."Itinerary_Variation_Identifier",'legSequence',l."Leg_Sequence_Number",'serviceType',l."Service_Type",'periodStart',l."Period_Start_Date",'periodEnd',l."Period_End_Date",'operatingDays',l."Operating_Days"::text,'departureAirport',btrim(l."Departure_Airport_IATA"),'arrivalAirport',btrim(l."Arrival_Airport_IATA"),'departureTime',to_char(l."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(l."Arrival_Time_Local",'HH24:MI'),'arrivalDayOffset',l."Arrival_Day_Offset",'aircraftType',l."Aircraft_Type_IATA",'aircraftSubtype',l."Aircraft_Series_Subtype",'aircraftConfiguration',l."Aircraft_Configuration",'parameters',case when p."Schedule_Leg_ID" is null then null else jsonb_build_object('aircraftSubtype',p."Aircraft_Series_Subtype",'crewCode',btrim(p."Crew_Code_ID"),'pantryCode',btrim(p."Pantry_Code_ID"),'passengerWeightBasis',p."Passenger_Weight_Basis",'passengerVariation',p."Passenger_Flight_Variation",'baggageWeightBasis',p."Baggage_Weight_Basis",'baggageVariation',p."Baggage_Flight_Variation",'remarks',coalesce(p."Remarks",'')) end) order by l."Flight_Number",l."Itinerary_Variation_Identifier",l."Leg_Sequence_Number",l."Period_Start_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l left join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p using("Schedule_Leg_ID") where l."Import_ID"=published_id),'[]'::jsonb),
  'serviceTypes',"Basic_Carrier_Record".get_flight_schedule_service_types(),
  'airports',coalesce((select jsonb_agg(jsonb_build_object('iata',btrim(a."Airport_IATA"),'icao',nullif(btrim(a."Airport_ICAO"),''),'name',btrim(a."Airport_Name"),'city',coalesce(btrim(a."City_Name"),''),'countryCode',nullif(btrim(a."Country_Code"),''),'timeZone',a."IANA_Time_Zone") order by a."Airport_IATA") from "Basic_Carrier_Record"."MASTER_Airports" a where a."Active"),'[]'::jsonb),
  'aircraft',coalesce((select jsonb_agg(jsonb_build_object('typeCode',a."Aircraft_Type_IATA",'subtype',a."Aircraft_Series_Subtype",'name',btrim(a."Aircraft_Type"),'operatingRole',a."Aircraft_Operating_Role") order by a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype") from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata),'[]'::jsonb),
  'aircraftConfigurations',coalesce((select jsonb_agg(jsonb_build_object('typeCode',x."Aircraft_Type_IATA",'subtype',x."Aircraft_Series_Subtype",'code',x."Configuration_Code",'description',x."Configuration_Code_Description") order by x."Aircraft_Type_IATA",x."Aircraft_Series_Subtype",x."Configuration_Code") from(select "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Configuration_Code") "Configuration_Code",min(btrim("Configuration_Code_Description")) "Configuration_Code_Description" from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata group by "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Configuration_Code"))x),'[]'::jsonb),
  'crewCodes',coalesce((select jsonb_agg(jsonb_build_object('typeCode',x."Aircraft_Type_IATA",'subtype',x."Aircraft_Series_Subtype",'code',x."Crew_Code_ID") order by x."Aircraft_Type_IATA",x."Aircraft_Series_Subtype",x."Crew_Code_ID") from(select distinct "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Crew_Code_ID") "Crew_Code_ID" from "Basic_Carrier_Record"."Aircraft_Crew_Codes" where "Carrier_IATA"=p_iata)x),'[]'::jsonb),
  'pantryCodes',coalesce((select jsonb_agg(jsonb_build_object('typeCode',x."Aircraft_Type_IATA",'subtype',x."Aircraft_Series_Subtype",'code',x."Pantry_Code_ID") order by x."Aircraft_Type_IATA",x."Aircraft_Series_Subtype",x."Pantry_Code_ID") from(select distinct "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Pantry_Code_ID") "Pantry_Code_ID" from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" where "Carrier_IATA"=p_iata)x),'[]'::jsonb),
  'variations',coalesce((select jsonb_agg(jsonb_build_object('code',"Flight_Type_Variation",'description',"Flight_Type_Variation_Description") order by "Flight_Type_Variation") from "Basic_Carrier_Record"."Carrier_Flight_Variations" where "Carrier_IATA"=p_iata),'[]'::jsonb)
 ) into payload;
 return payload;
end $$;


notify pgrst,'reload schema';
commit;
