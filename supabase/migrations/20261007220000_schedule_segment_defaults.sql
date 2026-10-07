begin;

create table "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults"(
  "Carrier_IATA" varchar(2) not null references "Basic_Carrier_Record"."MASTER_Carrier_Contact"("Carrier_IATA") on update cascade on delete cascade,
  "Departure_Airport_IATA" char(3) not null references "Basic_Carrier_Record"."MASTER_Airports"("Airport_IATA") on update cascade on delete restrict,
  "Arrival_Airport_IATA" char(3) not null references "Basic_Carrier_Record"."MASTER_Airports"("Airport_IATA") on update cascade on delete restrict,
  "Aircraft_Type_IATA" varchar(4) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Crew_Code_ID" varchar(1) not null check("Crew_Code_ID" ~ '^[A-Z0-9]$'),
  "Pantry_Code_ID" varchar(1) not null check("Pantry_Code_ID" ~ '^[A-Z0-9]$'),
  "Passenger_Weight_Basis" text not null check("Passenger_Weight_Basis" in('STANDARD','VARIATION','ACTUAL')),
  "Passenger_Flight_Variation" varchar(3),
  "Baggage_Weight_Basis" text not null check("Baggage_Weight_Basis" in('STANDARD','VARIATION','ACTUAL')),
  "Baggage_Flight_Variation" varchar(3),
  "Remarks" text,
  "Updated_By" uuid not null default auth.uid(),
  "Updated_At" timestamptz not null default now(),
  primary key("Carrier_IATA","Departure_Airport_IATA","Arrival_Airport_IATA","Aircraft_Type_IATA"),
  constraint "Schedule_Segment_Defaults_route_check" check("Departure_Airport_IATA"<>"Arrival_Airport_IATA"),
  constraint "Schedule_Segment_Defaults_passenger_check" check(("Passenger_Weight_Basis"='VARIATION' and "Passenger_Flight_Variation" is not null) or ("Passenger_Weight_Basis"<>'VARIATION' and "Passenger_Flight_Variation" is null)),
  constraint "Schedule_Segment_Defaults_baggage_check" check(("Baggage_Weight_Basis"='VARIATION' and "Baggage_Flight_Variation" is not null) or ("Baggage_Weight_Basis"<>'VARIATION' and "Baggage_Flight_Variation" is null)),
  constraint "Schedule_Segment_Defaults_remarks_check" check(char_length(coalesce("Remarks",''))<=1000)
);

create index "schedule_segment_defaults_carrier_route_idx" on "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults"("Carrier_IATA","Departure_Airport_IATA","Arrival_Airport_IATA");
alter table "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" enable row level security;
revoke all on "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" from public,anon,authenticated;

alter table "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"
  add column "Parameter_Source" text not null default 'FLIGHT_OVERRIDE'
  check("Parameter_Source" in('SEGMENT_DEFAULT','FLIGHT_OVERRIDE'));

create or replace function "Basic_Carrier_Record".get_flight_schedule_segment_defaults(p_iata text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW')) then raise exception 'Flight schedule access denied' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'departureAirport',btrim(d."Departure_Airport_IATA"),'arrivalAirport',btrim(d."Arrival_Airport_IATA"),'aircraftType',d."Aircraft_Type_IATA",
  'aircraftSubtype',d."Aircraft_Series_Subtype",'crewCode',btrim(d."Crew_Code_ID"),'pantryCode',btrim(d."Pantry_Code_ID"),
  'passengerWeightBasis',d."Passenger_Weight_Basis",'passengerVariation',d."Passenger_Flight_Variation",
  'baggageWeightBasis',d."Baggage_Weight_Basis",'baggageVariation',d."Baggage_Flight_Variation",'remarks',coalesce(d."Remarks",''),
  'updatedAt',d."Updated_At") order by d."Departure_Airport_IATA",d."Arrival_Airport_IATA",d."Aircraft_Type_IATA")
 from "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" d where d."Carrier_IATA"=p_iata),'[]'::jsonb);
end $$;

create or replace function "Basic_Carrier_Record".save_flight_schedule_segment_default(p_iata text,p_departure_airport text,p_arrival_airport text,p_aircraft_type text,p_values jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare subtype text;crew text;pantry text;passenger_basis text;passenger_variation text;baggage_basis text;baggage_variation text;remarks text;published_id uuid;
begin
 p_iata:=upper(btrim(p_iata));p_departure_airport:=upper(btrim(p_departure_airport));p_arrival_airport:=upper(btrim(p_arrival_airport));p_aircraft_type:=upper(btrim(p_aircraft_type));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Flight schedule configuration access denied' using errcode='42501';end if;
 if p_departure_airport!~'^[A-Z]{3}$' or p_arrival_airport!~'^[A-Z]{3}$' or p_departure_airport=p_arrival_airport or p_aircraft_type!~'^[A-Z0-9]{2,4}$' then raise exception 'Select a valid directional segment and aircraft type' using errcode='22023';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Segment defaults are required' using errcode='22023';end if;
 subtype:=upper(btrim(p_values->>'aircraftSubtype'));crew:=upper(btrim(p_values->>'crewCode'));pantry:=upper(btrim(p_values->>'pantryCode'));
 passenger_basis:=upper(btrim(p_values->>'passengerWeightBasis'));passenger_variation:=nullif(upper(btrim(p_values->>'passengerVariation')),'');
 baggage_basis:=upper(btrim(p_values->>'baggageWeightBasis'));baggage_variation:=nullif(upper(btrim(p_values->>'baggageVariation')),'');remarks:=nullif(btrim(p_values->>'remarks'),'');
 if not exists(select 1 from "Basic_Carrier_Record"."MASTER_Airports" a where a."Airport_IATA" in(p_departure_airport,p_arrival_airport) and a."Active" having count(*)=2) then raise exception 'Select active airports for the segment' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=p_aircraft_type and a."Aircraft_Series_Subtype"=subtype) then raise exception 'Select a configured aircraft subtype matching the segment aircraft type' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=p_aircraft_type and c."Aircraft_Series_Subtype"=subtype and btrim(c."Crew_Code_ID")=crew) then raise exception 'Select a valid crew code' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=p_aircraft_type and p."Aircraft_Series_Subtype"=subtype and btrim(p."Pantry_Code_ID")=pantry) then raise exception 'Select a valid pantry code' using errcode='23503';end if;
 if passenger_basis not in('STANDARD','VARIATION','ACTUAL') or baggage_basis not in('STANDARD','VARIATION','ACTUAL') then raise exception 'Select passenger and baggage weight methods' using errcode='22023';end if;
 if (passenger_basis='VARIATION')<>(passenger_variation is not null) or (baggage_basis='VARIATION')<>(baggage_variation is not null) then raise exception 'Select the required flight variation' using errcode='22023';end if;
 if passenger_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=passenger_variation) then raise exception 'Passenger variation not found' using errcode='23503';end if;
 if baggage_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=baggage_variation) then raise exception 'Baggage variation not found' using errcode='23503';end if;
 if char_length(coalesce(remarks,''))>1000 then raise exception 'Remarks are too long' using errcode='22023';end if;
 insert into "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" as existing("Carrier_IATA","Departure_Airport_IATA","Arrival_Airport_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Updated_By","Updated_At")
 values(p_iata,p_departure_airport,p_arrival_airport,p_aircraft_type,subtype,crew,pantry,passenger_basis,passenger_variation,baggage_basis,baggage_variation,remarks,auth.uid(),now())
 on conflict("Carrier_IATA","Departure_Airport_IATA","Arrival_Airport_IATA","Aircraft_Type_IATA") do update set "Aircraft_Series_Subtype"=excluded."Aircraft_Series_Subtype","Crew_Code_ID"=excluded."Crew_Code_ID","Pantry_Code_ID"=excluded."Pantry_Code_ID","Passenger_Weight_Basis"=excluded."Passenger_Weight_Basis","Passenger_Flight_Variation"=excluded."Passenger_Flight_Variation","Baggage_Weight_Basis"=excluded."Baggage_Weight_Basis","Baggage_Flight_Variation"=excluded."Baggage_Flight_Variation","Remarks"=excluded."Remarks","Updated_By"=auth.uid(),"Updated_At"=now();
 select "Import_ID" into published_id from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=p_iata and "Status"='PUBLISHED';
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" as existing("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At")
 select l."Schedule_Leg_ID",p_iata,subtype,crew,pantry,passenger_basis,passenger_variation,baggage_basis,baggage_variation,remarks,'SEGMENT_DEFAULT',auth.uid(),now() from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=published_id and l."Departure_Airport_IATA"=p_departure_airport and l."Arrival_Airport_IATA"=p_arrival_airport and l."Aircraft_Type_IATA"=p_aircraft_type
 on conflict("Schedule_Leg_ID") do update set "Aircraft_Series_Subtype"=excluded."Aircraft_Series_Subtype","Crew_Code_ID"=excluded."Crew_Code_ID","Pantry_Code_ID"=excluded."Pantry_Code_ID","Passenger_Weight_Basis"=excluded."Passenger_Weight_Basis","Passenger_Flight_Variation"=excluded."Passenger_Flight_Variation","Baggage_Weight_Basis"=excluded."Baggage_Weight_Basis","Baggage_Flight_Variation"=excluded."Baggage_Flight_Variation","Remarks"=excluded."Remarks","Updated_By"=auth.uid(),"Updated_At"=now() where existing."Parameter_Source"='SEGMENT_DEFAULT';
end $$;

create or replace function "Basic_Carrier_Record".delete_flight_schedule_segment_default(p_iata text,p_departure_airport text,p_arrival_airport text,p_aircraft_type text)
returns void language plpgsql security definer set search_path='' as $$
declare published_id uuid;
begin
 p_iata:=upper(btrim(p_iata));p_departure_airport:=upper(btrim(p_departure_airport));p_arrival_airport:=upper(btrim(p_arrival_airport));p_aircraft_type:=upper(btrim(p_aircraft_type));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Flight schedule configuration access denied' using errcode='42501';end if;
 select "Import_ID" into published_id from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=p_iata and "Status"='PUBLISHED';
 delete from "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p using "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where p."Schedule_Leg_ID"=l."Schedule_Leg_ID" and p."Parameter_Source"='SEGMENT_DEFAULT' and l."Import_ID"=published_id and l."Departure_Airport_IATA"=p_departure_airport and l."Arrival_Airport_IATA"=p_arrival_airport and l."Aircraft_Type_IATA"=p_aircraft_type;
 delete from "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" where "Carrier_IATA"=p_iata and "Departure_Airport_IATA"=p_departure_airport and "Arrival_Airport_IATA"=p_arrival_airport and "Aircraft_Type_IATA"=p_aircraft_type;
end $$;

create or replace function "Basic_Carrier_Record".save_flight_schedule_leg_parameters(p_iata text,p_schedule_leg_id uuid,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare leg "Basic_Carrier_Record"."Scheduled_Flight_Legs"%rowtype;subtype text;crew text;pantry text;passenger_basis text;passenger_variation text;baggage_basis text;baggage_variation text;remarks text;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Flight schedule configuration access denied' using errcode='42501';end if;
 select l.* into leg from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l join "Basic_Carrier_Record"."Flight_Schedule_Imports" i using("Import_ID") where l."Schedule_Leg_ID"=p_schedule_leg_id and l."Carrier_IATA"=p_iata and i."Status"='PUBLISHED';
 if not found then raise exception 'Published schedule leg not found' using errcode='P0002';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Load Control parameters are required' using errcode='22023';end if;
 subtype:=upper(btrim(p_values->>'aircraftSubtype'));crew:=upper(btrim(p_values->>'crewCode'));pantry:=upper(btrim(p_values->>'pantryCode'));passenger_basis:=upper(btrim(p_values->>'passengerWeightBasis'));passenger_variation:=nullif(upper(btrim(p_values->>'passengerVariation')),'');baggage_basis:=upper(btrim(p_values->>'baggageWeightBasis'));baggage_variation:=nullif(upper(btrim(p_values->>'baggageVariation')),'');remarks:=nullif(btrim(p_values->>'remarks'),'');
 if leg."Aircraft_Type_IATA" is null or not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=leg."Aircraft_Type_IATA" and a."Aircraft_Series_Subtype"=subtype) then raise exception 'Select a configured aircraft subtype matching the scheduled aircraft type' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=leg."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=subtype and btrim(c."Crew_Code_ID")=crew) then raise exception 'Select a valid crew code' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=leg."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=subtype and btrim(p."Pantry_Code_ID")=pantry) then raise exception 'Select a valid pantry code' using errcode='23503';end if;
 if passenger_basis not in('STANDARD','VARIATION','ACTUAL') or baggage_basis not in('STANDARD','VARIATION','ACTUAL') then raise exception 'Select passenger and baggage weight methods' using errcode='22023';end if;
 if (passenger_basis='VARIATION')<>(passenger_variation is not null) or (baggage_basis='VARIATION')<>(baggage_variation is not null) then raise exception 'Select the required flight variation' using errcode='22023';end if;
 if passenger_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=passenger_variation) then raise exception 'Passenger variation not found' using errcode='23503';end if;
 if baggage_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=baggage_variation) then raise exception 'Baggage variation not found' using errcode='23503';end if;
 if char_length(coalesce(remarks,''))>1000 then raise exception 'Remarks are too long' using errcode='22023';end if;
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At") values(p_schedule_leg_id,p_iata,subtype,crew,pantry,passenger_basis,passenger_variation,baggage_basis,baggage_variation,remarks,'FLIGHT_OVERRIDE',auth.uid(),now())
 on conflict("Schedule_Leg_ID") do update set "Aircraft_Series_Subtype"=excluded."Aircraft_Series_Subtype","Crew_Code_ID"=excluded."Crew_Code_ID","Pantry_Code_ID"=excluded."Pantry_Code_ID","Passenger_Weight_Basis"=excluded."Passenger_Weight_Basis","Passenger_Flight_Variation"=excluded."Passenger_Flight_Variation","Baggage_Weight_Basis"=excluded."Baggage_Weight_Basis","Baggage_Flight_Variation"=excluded."Baggage_Flight_Variation","Remarks"=excluded."Remarks","Parameter_Source"='FLIGHT_OVERRIDE',"Updated_By"=auth.uid(),"Updated_At"=now();
 return "Basic_Carrier_Record".get_flight_schedule_workspace(p_iata);
end $$;

create or replace function private.copy_schedule_parameters_to_new_publication()
returns trigger language plpgsql security definer set search_path='' as $$
declare previous_id uuid;
begin
 if new."Status"<>'PUBLISHED' or old."Status"='PUBLISHED' then return new;end if;
 select "Import_ID" into previous_id from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=new."Carrier_IATA" and "Status"='SUPERSEDED' and "Import_ID"<>new."Import_ID" order by "Superseded_At" desc nulls last limit 1;
 if previous_id is not null then
  insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At")
  select target."Schedule_Leg_ID",new."Carrier_IATA",p."Aircraft_Series_Subtype",p."Crew_Code_ID",p."Pantry_Code_ID",p."Passenger_Weight_Basis",p."Passenger_Flight_Variation",p."Baggage_Weight_Basis",p."Baggage_Flight_Variation",p."Remarks",p."Parameter_Source",new."Published_By",now()
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs" source join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p on p."Schedule_Leg_ID"=source."Schedule_Leg_ID" join "Basic_Carrier_Record"."Scheduled_Flight_Legs" target on target."Import_ID"=new."Import_ID" and target."Airline_Designator"=source."Airline_Designator" and target."Flight_Number"=source."Flight_Number" and target."Operational_Suffix"=source."Operational_Suffix" and target."Itinerary_Variation_Identifier"=source."Itinerary_Variation_Identifier" and target."Leg_Sequence_Number"=source."Leg_Sequence_Number" and target."Departure_Airport_IATA"=source."Departure_Airport_IATA" and target."Arrival_Airport_IATA"=source."Arrival_Airport_IATA" and target."Aircraft_Type_IATA" is not distinct from source."Aircraft_Type_IATA" where source."Import_ID"=previous_id and p."Parameter_Source"='FLIGHT_OVERRIDE' on conflict("Schedule_Leg_ID") do nothing;
 end if;
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At")
 select l."Schedule_Leg_ID",new."Carrier_IATA",d."Aircraft_Series_Subtype",d."Crew_Code_ID",d."Pantry_Code_ID",d."Passenger_Weight_Basis",d."Passenger_Flight_Variation",d."Baggage_Weight_Basis",d."Baggage_Flight_Variation",d."Remarks",'SEGMENT_DEFAULT',new."Published_By",now() from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l join "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" d on d."Carrier_IATA"=new."Carrier_IATA" and d."Departure_Airport_IATA"=l."Departure_Airport_IATA" and d."Arrival_Airport_IATA"=l."Arrival_Airport_IATA" and d."Aircraft_Type_IATA"=l."Aircraft_Type_IATA" where l."Import_ID"=new."Import_ID" on conflict("Schedule_Leg_ID") do nothing;
 return new;
end $$;

create or replace function "Basic_Carrier_Record".create_manual_schedule_revision(p_iata text,p_source_import_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare source_import "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;source_leg "Basic_Carrier_Record"."Scheduled_Flight_Legs"%rowtype;source_parameters "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"%rowtype;new_import_id uuid;new_leg_id uuid;line_number integer:=0;revision_number integer;base_name text;revision_name text;hash text;parsed jsonb;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Schedule revision access denied' using errcode='42501';end if;
 select * into source_import from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_source_import_id and "Carrier_IATA"=p_iata and "Status"='PUBLISHED';
 if not found then raise exception 'Published schedule not found' using errcode='P0002';end if;
 base_name:=regexp_replace(source_import."Original_File_Name",' - Revision [0-9]+$','','i');revision_number:=coalesce(nullif(substring(source_import."Original_File_Name" from '(?i) - Revision ([0-9]+)$'),'')::integer,1)+1;revision_name:=base_name||' - Revision '||revision_number;hash:=md5(gen_random_uuid()::text||clock_timestamp()::text)||md5(gen_random_uuid()::text||p_iata);
 insert into "Basic_Carrier_Record"."Flight_Schedule_Imports"("Carrier_IATA","Source_Carrier_IATA","Source_Format","Original_File_Name","File_SHA256","File_Size_Bytes","Source_Encoding","Season_Code","Creator_Reference","Coverage_Start_Date","Coverage_End_Date","Status","Total_Record_Count","Accepted_Record_Count","Rejected_Record_Count","Normalized_Leg_Count","Validation_Summary","Uploaded_By","Validated_At") values(p_iata,p_iata,'MANUAL',revision_name,hash,1,'UTF-8',source_import."Season_Code",'Revision of '||source_import."Import_ID",source_import."Coverage_Start_Date",source_import."Coverage_End_Date",'VALIDATED',source_import."Normalized_Leg_Count",source_import."Normalized_Leg_Count",0,source_import."Normalized_Leg_Count",jsonb_build_object('valid',true,'source','MANUAL_REVISION','revisionOf',source_import."Import_ID"),auth.uid(),now()) returning "Import_ID" into new_import_id;
 for source_leg in select * from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Import_ID"=p_source_import_id order by "Source_Line_Number","Schedule_Leg_ID" loop
  line_number:=line_number+1;select * into source_parameters from "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" where "Schedule_Leg_ID"=source_leg."Schedule_Leg_ID";
  parsed:=jsonb_build_object('airlineDesignator',source_leg."Airline_Designator",'flightNumber',source_leg."Flight_Number",'operationalSuffix',source_leg."Operational_Suffix",'itineraryVariation',source_leg."Itinerary_Variation_Identifier",'legSequence',source_leg."Leg_Sequence_Number",'serviceType',source_leg."Service_Type",'periodStart',source_leg."Period_Start_Date",'periodEnd',source_leg."Period_End_Date",'operatingDays',source_leg."Operating_Days"::text,'departureAirport',btrim(source_leg."Departure_Airport_IATA"),'arrivalAirport',btrim(source_leg."Arrival_Airport_IATA"),'departureTime',to_char(source_leg."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(source_leg."Arrival_Time_Local",'HH24:MI'),'arrivalDayOffset',source_leg."Arrival_Day_Offset",'aircraftType',source_leg."Aircraft_Type_IATA",'aircraftSubtype',case when found then source_parameters."Aircraft_Series_Subtype" else null end,'aircraftConfiguration',source_leg."Aircraft_Configuration");
  insert into "Basic_Carrier_Record"."Flight_Schedule_Import_Records"("Import_ID","Carrier_IATA","Line_Number","Record_Type","Raw_Record","Parse_Status","Parsed_Data") values(new_import_id,p_iata,line_number,'M','MANUAL REVISION '||line_number,'PARSED',parsed);
  insert into "Basic_Carrier_Record"."Scheduled_Flight_Legs"("Import_ID","Carrier_IATA","Source_Line_Number","Airline_Designator","Flight_Number","Operational_Suffix","Itinerary_Variation_Identifier","Leg_Sequence_Number","Service_Type","Period_Start_Date","Period_End_Date","Operating_Days","Departure_Airport_IATA","Arrival_Airport_IATA","Departure_Time_Local","Arrival_Time_Local","Arrival_Day_Offset","Departure_UTC_Offset_Minutes","Arrival_UTC_Offset_Minutes","Departure_Terminal","Arrival_Terminal","Aircraft_Type_IATA","Aircraft_Configuration","Traffic_Restriction_Codes","Additional_Data") values(new_import_id,p_iata,line_number,source_leg."Airline_Designator",source_leg."Flight_Number",source_leg."Operational_Suffix",source_leg."Itinerary_Variation_Identifier",source_leg."Leg_Sequence_Number",source_leg."Service_Type",source_leg."Period_Start_Date",source_leg."Period_End_Date",source_leg."Operating_Days",source_leg."Departure_Airport_IATA",source_leg."Arrival_Airport_IATA",source_leg."Departure_Time_Local",source_leg."Arrival_Time_Local",source_leg."Arrival_Day_Offset",source_leg."Departure_UTC_Offset_Minutes",source_leg."Arrival_UTC_Offset_Minutes",source_leg."Departure_Terminal",source_leg."Arrival_Terminal",source_leg."Aircraft_Type_IATA",source_leg."Aircraft_Configuration",source_leg."Traffic_Restriction_Codes",source_leg."Additional_Data"||jsonb_build_object('source','MANUAL_REVISION','revisionOfLegId',source_leg."Schedule_Leg_ID")) returning "Schedule_Leg_ID" into new_leg_id;
  if found and source_parameters."Schedule_Leg_ID" is not null and source_parameters."Parameter_Source"='FLIGHT_OVERRIDE' then
   insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At") values(new_leg_id,p_iata,source_parameters."Aircraft_Series_Subtype",source_parameters."Crew_Code_ID",source_parameters."Pantry_Code_ID",source_parameters."Passenger_Weight_Basis",source_parameters."Passenger_Flight_Variation",source_parameters."Baggage_Weight_Basis",source_parameters."Baggage_Flight_Variation",source_parameters."Remarks",'FLIGHT_OVERRIDE',auth.uid(),now());
  end if;
 end loop;
 return new_import_id;
end $$;

revoke all on function "Basic_Carrier_Record".get_flight_schedule_segment_defaults(text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_flight_schedule_segment_default(text,text,text,text,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".delete_flight_schedule_segment_default(text,text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_flight_schedule_segment_defaults(text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_flight_schedule_segment_default(text,text,text,text,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".delete_flight_schedule_segment_default(text,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
