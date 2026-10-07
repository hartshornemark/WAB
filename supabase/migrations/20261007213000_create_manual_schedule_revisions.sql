begin;

create function "Basic_Carrier_Record".create_manual_schedule_revision(p_iata text,p_source_import_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare
 source_import "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;
 source_leg "Basic_Carrier_Record"."Scheduled_Flight_Legs"%rowtype;
 source_parameters "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"%rowtype;
 new_import_id uuid;
 new_leg_id uuid;
 line_number integer:=0;
 revision_number integer;
 base_name text;
 revision_name text;
 hash text;
 parsed jsonb;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then
  raise exception 'Schedule revision access denied' using errcode='42501';
 end if;
 select * into source_import from "Basic_Carrier_Record"."Flight_Schedule_Imports"
 where "Import_ID"=p_source_import_id and "Carrier_IATA"=p_iata and "Status"='PUBLISHED';
 if not found then raise exception 'Published schedule not found' using errcode='P0002';end if;

 base_name:=regexp_replace(source_import."Original_File_Name",' - Revision [0-9]+$','','i');
 revision_number:=coalesce(nullif(substring(source_import."Original_File_Name" from '(?i) - Revision ([0-9]+)$'),'')::integer,1)+1;
 revision_name:=base_name||' - Revision '||revision_number;
 hash:=md5(gen_random_uuid()::text||clock_timestamp()::text)||md5(gen_random_uuid()::text||p_iata);
 insert into "Basic_Carrier_Record"."Flight_Schedule_Imports"(
  "Carrier_IATA","Source_Carrier_IATA","Source_Format","Original_File_Name","File_SHA256","File_Size_Bytes","Source_Encoding","Season_Code","Creator_Reference","Coverage_Start_Date","Coverage_End_Date","Status","Total_Record_Count","Accepted_Record_Count","Rejected_Record_Count","Normalized_Leg_Count","Validation_Summary","Uploaded_By","Validated_At"
 ) values(
  p_iata,p_iata,'MANUAL',revision_name,hash,1,'UTF-8',source_import."Season_Code",'Revision of '||source_import."Import_ID",source_import."Coverage_Start_Date",source_import."Coverage_End_Date",'VALIDATED',source_import."Normalized_Leg_Count",source_import."Normalized_Leg_Count",0,source_import."Normalized_Leg_Count",jsonb_build_object('valid',true,'source','MANUAL_REVISION','revisionOf',source_import."Import_ID"),auth.uid(),now()
 ) returning "Import_ID" into new_import_id;

 for source_leg in select * from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Import_ID"=p_source_import_id order by "Source_Line_Number","Schedule_Leg_ID" loop
  line_number:=line_number+1;
  select * into source_parameters from "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" where "Schedule_Leg_ID"=source_leg."Schedule_Leg_ID";
  parsed:=jsonb_build_object(
   'airlineDesignator',source_leg."Airline_Designator",'flightNumber',source_leg."Flight_Number",'operationalSuffix',source_leg."Operational_Suffix",'itineraryVariation',source_leg."Itinerary_Variation_Identifier",'legSequence',source_leg."Leg_Sequence_Number",'serviceType',source_leg."Service_Type",'periodStart',source_leg."Period_Start_Date",'periodEnd',source_leg."Period_End_Date",'operatingDays',source_leg."Operating_Days"::text,'departureAirport',btrim(source_leg."Departure_Airport_IATA"),'arrivalAirport',btrim(source_leg."Arrival_Airport_IATA"),'departureTime',to_char(source_leg."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(source_leg."Arrival_Time_Local",'HH24:MI'),'arrivalDayOffset',source_leg."Arrival_Day_Offset",'aircraftType',source_leg."Aircraft_Type_IATA",'aircraftSubtype',case when found then source_parameters."Aircraft_Series_Subtype" else null end,'aircraftConfiguration',source_leg."Aircraft_Configuration"
  );
  insert into "Basic_Carrier_Record"."Flight_Schedule_Import_Records"("Import_ID","Carrier_IATA","Line_Number","Record_Type","Raw_Record","Parse_Status","Parsed_Data")
  values(new_import_id,p_iata,line_number,'M','MANUAL REVISION '||line_number,'PARSED',parsed);
  insert into "Basic_Carrier_Record"."Scheduled_Flight_Legs"(
   "Import_ID","Carrier_IATA","Source_Line_Number","Airline_Designator","Flight_Number","Operational_Suffix","Itinerary_Variation_Identifier","Leg_Sequence_Number","Service_Type","Period_Start_Date","Period_End_Date","Operating_Days","Departure_Airport_IATA","Arrival_Airport_IATA","Departure_Time_Local","Arrival_Time_Local","Arrival_Day_Offset","Departure_UTC_Offset_Minutes","Arrival_UTC_Offset_Minutes","Departure_Terminal","Arrival_Terminal","Aircraft_Type_IATA","Aircraft_Configuration","Traffic_Restriction_Codes","Additional_Data"
  ) values(
   new_import_id,p_iata,line_number,source_leg."Airline_Designator",source_leg."Flight_Number",source_leg."Operational_Suffix",source_leg."Itinerary_Variation_Identifier",source_leg."Leg_Sequence_Number",source_leg."Service_Type",source_leg."Period_Start_Date",source_leg."Period_End_Date",source_leg."Operating_Days",source_leg."Departure_Airport_IATA",source_leg."Arrival_Airport_IATA",source_leg."Departure_Time_Local",source_leg."Arrival_Time_Local",source_leg."Arrival_Day_Offset",source_leg."Departure_UTC_Offset_Minutes",source_leg."Arrival_UTC_Offset_Minutes",source_leg."Departure_Terminal",source_leg."Arrival_Terminal",source_leg."Aircraft_Type_IATA",source_leg."Aircraft_Configuration",source_leg."Traffic_Restriction_Codes",source_leg."Additional_Data"||jsonb_build_object('source','MANUAL_REVISION','revisionOfLegId',source_leg."Schedule_Leg_ID")
  ) returning "Schedule_Leg_ID" into new_leg_id;
  if found and source_parameters."Schedule_Leg_ID" is not null then
   insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Updated_By","Updated_At")
   values(new_leg_id,p_iata,source_parameters."Aircraft_Series_Subtype",source_parameters."Crew_Code_ID",source_parameters."Pantry_Code_ID",source_parameters."Passenger_Weight_Basis",source_parameters."Passenger_Flight_Variation",source_parameters."Baggage_Weight_Basis",source_parameters."Baggage_Flight_Variation",source_parameters."Remarks",auth.uid(),now());
  end if;
 end loop;
 return new_import_id;
end $$;

revoke all on function "Basic_Carrier_Record".create_manual_schedule_revision(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".create_manual_schedule_revision(text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
