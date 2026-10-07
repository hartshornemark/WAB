begin;

alter table "Basic_Carrier_Record"."Flight_Schedule_Imports"
  add column "Schedule_Family_ID" uuid,
  add column "Supersedes_Import_ID" uuid,
  add column "Cancelled_By" uuid,
  add column "Cancelled_At" timestamptz;

update "Basic_Carrier_Record"."Flight_Schedule_Imports"
set "Schedule_Family_ID"="Import_ID";

update "Basic_Carrier_Record"."Flight_Schedule_Imports" child
set "Supersedes_Import_ID"=(child."Validation_Summary"->>'revisionOf')::uuid
where coalesce(child."Validation_Summary"->>'revisionOf','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and exists(select 1 from "Basic_Carrier_Record"."Flight_Schedule_Imports" parent where parent."Import_ID"=(child."Validation_Summary"->>'revisionOf')::uuid and parent."Carrier_IATA"=child."Carrier_IATA");

with recursive family_tree as(
 select i."Import_ID",i."Import_ID" family_id
 from "Basic_Carrier_Record"."Flight_Schedule_Imports" i
 where i."Supersedes_Import_ID" is null
 union all
 select child."Import_ID",parent.family_id
 from family_tree parent
 join "Basic_Carrier_Record"."Flight_Schedule_Imports" child on child."Supersedes_Import_ID"=parent."Import_ID"
)
update "Basic_Carrier_Record"."Flight_Schedule_Imports" i
set "Schedule_Family_ID"=tree.family_id
from family_tree tree where tree."Import_ID"=i."Import_ID";

alter table "Basic_Carrier_Record"."Flight_Schedule_Imports"
  alter column "Schedule_Family_ID" set default gen_random_uuid(),
  alter column "Schedule_Family_ID" set not null,
  add constraint "Flight_Schedule_Imports_Supersedes_fkey" foreign key("Supersedes_Import_ID") references "Basic_Carrier_Record"."Flight_Schedule_Imports"("Import_ID") on update cascade on delete restrict;

alter table "Basic_Carrier_Record"."Flight_Schedule_Imports"
  drop constraint "Flight_Schedule_Imports_Status_check",
  add constraint "Flight_Schedule_Imports_Status_check" check("Status" in('DRAFT','VALIDATED','PUBLISHED','REJECTED','SUPERSEDED','CANCELLED'));

drop index "Basic_Carrier_Record"."flight_schedule_one_published_import_per_carrier";
create unique index "flight_schedule_one_published_import_per_family"
  on "Basic_Carrier_Record"."Flight_Schedule_Imports"("Carrier_IATA","Schedule_Family_ID")
  where "Status"='PUBLISHED';
create index "flight_schedule_published_carrier_idx"
  on "Basic_Carrier_Record"."Flight_Schedule_Imports"("Carrier_IATA","Status")
  where "Status"='PUBLISHED';

comment on table "Basic_Carrier_Record"."Flight_Schedule_Imports" is
  'Independent schedule families and their immutable editions. Multiple families may be published concurrently; publishing a revision supersedes only its own family.';

create or replace function "Basic_Carrier_Record".publish_ssim_schedule_import(p_iata text,p_import_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_PUBLISH') or private.has_global_permission('FLIGHT_SCHEDULE_PUBLISH')) then raise exception 'Flight schedule publication access denied' using errcode='42501';end if;
 select * into target from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata for update;
 if not found then raise exception 'Schedule edition not found' using errcode='P0002';end if;
 if target."Status"<>'VALIDATED' or target."Rejected_Record_Count"<>0 or target."Normalized_Leg_Count"=0 or target."Coverage_Start_Date" is null then raise exception 'Only a completely validated schedule edition can be published' using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('published-schedule-family:'||p_iata||':'||target."Schedule_Family_ID",0));
 update "Basic_Carrier_Record"."Flight_Schedule_Imports" set "Status"='SUPERSEDED',"Superseded_At"=now() where "Carrier_IATA"=p_iata and "Schedule_Family_ID"=target."Schedule_Family_ID" and "Status"='PUBLISHED' and "Import_ID"<>p_import_id;
 update "Basic_Carrier_Record"."Flight_Schedule_Imports" set "Status"='PUBLISHED',"Published_By"=auth.uid(),"Published_At"=now(),"Superseded_At"=null,"Cancelled_By"=null,"Cancelled_At"=null where "Import_ID"=p_import_id;
 return jsonb_build_object('importId',p_import_id,'status','PUBLISHED','carrierIata',p_iata,'coverageStart',target."Coverage_Start_Date",'coverageEnd',target."Coverage_End_Date",'normalizedLegs',target."Normalized_Leg_Count");
end $$;

create or replace function "Basic_Carrier_Record".cancel_flight_schedule_edition(p_iata text,p_import_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_PUBLISH') or private.has_global_permission('FLIGHT_SCHEDULE_PUBLISH')) then raise exception 'Flight schedule cancellation access denied' using errcode='42501';end if;
 update "Basic_Carrier_Record"."Flight_Schedule_Imports" set "Status"='CANCELLED',"Cancelled_By"=auth.uid(),"Cancelled_At"=now() where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata and "Status"='PUBLISHED';
 if not found then raise exception 'Published schedule not found' using errcode='P0002';end if;
end $$;

create or replace function "Basic_Carrier_Record".get_flight_schedule_workspace(p_iata text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare can_view boolean;can_configure boolean;published_ids uuid[];payload jsonb;
begin
 p_iata:=upper(btrim(p_iata));
 can_view:=(select auth.uid()) is not null and(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW'));
 can_configure:=private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE');
 if not can_view then raise exception 'Flight schedule access denied' using errcode='42501';end if;
 select coalesce(array_agg("Import_ID" order by "Published_At","Import_ID"),'{}'::uuid[]) into published_ids from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=p_iata and "Status"='PUBLISHED';
 select jsonb_build_object(
  'canView',can_view,'canConfigure',can_configure,'publishedImportIds',to_jsonb(published_ids),
  'legs',coalesce((select jsonb_agg(jsonb_build_object('scheduleImportId',i."Import_ID",'scheduleFamilyId',i."Schedule_Family_ID",'scheduleName',i."Original_File_Name",'scheduleLegId',l."Schedule_Leg_ID",'flightNumber',l."Flight_Number",'operationalSuffix',l."Operational_Suffix",'itineraryVariation',l."Itinerary_Variation_Identifier",'legSequence',l."Leg_Sequence_Number",'serviceType',l."Service_Type",'periodStart',l."Period_Start_Date",'periodEnd',l."Period_End_Date",'operatingDays',l."Operating_Days"::text,'departureAirport',btrim(l."Departure_Airport_IATA"),'arrivalAirport',btrim(l."Arrival_Airport_IATA"),'departureTime',to_char(l."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(l."Arrival_Time_Local",'HH24:MI'),'arrivalDayOffset',l."Arrival_Day_Offset",'aircraftType',l."Aircraft_Type_IATA",'aircraftSubtype',l."Aircraft_Series_Subtype",'aircraftConfiguration',l."Aircraft_Configuration",'parameters',case when p."Schedule_Leg_ID" is null then null else jsonb_build_object('aircraftSubtype',p."Aircraft_Series_Subtype",'crewCode',btrim(p."Crew_Code_ID"),'pantryCode',btrim(p."Pantry_Code_ID"),'passengerWeightBasis',p."Passenger_Weight_Basis",'passengerVariation',p."Passenger_Flight_Variation",'baggageWeightBasis',p."Baggage_Weight_Basis",'baggageVariation',p."Baggage_Flight_Variation",'remarks',coalesce(p."Remarks",'')) end) order by i."Original_File_Name",l."Flight_Number",l."Itinerary_Variation_Identifier",l."Leg_Sequence_Number",l."Period_Start_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l join "Basic_Carrier_Record"."Flight_Schedule_Imports" i using("Import_ID") left join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p using("Schedule_Leg_ID") where i."Carrier_IATA"=p_iata and i."Status"='PUBLISHED'),'[]'::jsonb),
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

create or replace function "Basic_Carrier_Record".refresh_flight_schedule_only_choice_defaults(p_iata text)
returns void language plpgsql security definer set search_path='' as $$
declare item record;actor uuid;
begin
 p_iata:=upper(btrim(p_iata));actor:=(select auth.uid());
 if actor is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW')) then raise exception 'Flight schedule access denied' using errcode='42501';end if;
 for item in select "Import_ID" from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=p_iata and "Status"='PUBLISHED' loop
  delete from "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p using "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where p."Schedule_Leg_ID"=l."Schedule_Leg_ID" and l."Import_ID"=item."Import_ID" and p."Parameter_Source"='ONLY_CHOICE_DEFAULT';
  perform private.apply_schedule_only_choice_defaults(p_iata,item."Import_ID",actor);
 end loop;
end $$;

create or replace function "Basic_Carrier_Record".save_flight_schedule_segment_default(p_iata text,p_departure_airport text,p_arrival_airport text,p_aircraft_type text,p_values jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare subtype text;crew text;pantry text;passenger_basis text;passenger_variation text;baggage_basis text;baggage_variation text;remarks text;
begin
 p_iata:=upper(btrim(p_iata));p_departure_airport:=upper(btrim(p_departure_airport));p_arrival_airport:=upper(btrim(p_arrival_airport));p_aircraft_type:=upper(btrim(p_aircraft_type));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Flight schedule configuration access denied' using errcode='42501';end if;
 if p_departure_airport!~'^[A-Z]{3}$' or p_arrival_airport!~'^[A-Z]{3}$' or p_departure_airport=p_arrival_airport or p_aircraft_type!~'^[A-Z0-9]{2,4}$' then raise exception 'Select a valid directional segment and aircraft type' using errcode='22023';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Segment defaults are required' using errcode='22023';end if;
 subtype:=upper(btrim(p_values->>'aircraftSubtype'));crew:=upper(btrim(p_values->>'crewCode'));pantry:=upper(btrim(p_values->>'pantryCode'));passenger_basis:=upper(btrim(p_values->>'passengerWeightBasis'));passenger_variation:=nullif(upper(btrim(p_values->>'passengerVariation')),'');baggage_basis:=upper(btrim(p_values->>'baggageWeightBasis'));baggage_variation:=nullif(upper(btrim(p_values->>'baggageVariation')),'');remarks:=nullif(btrim(p_values->>'remarks'),'');
 if not exists(select 1 from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l join "Basic_Carrier_Record"."Flight_Schedule_Imports" i using("Import_ID") where i."Carrier_IATA"=p_iata and i."Status"='PUBLISHED' and btrim(l."Departure_Airport_IATA")=p_departure_airport and btrim(l."Arrival_Airport_IATA")=p_arrival_airport and l."Aircraft_Type_IATA"=p_aircraft_type) then raise exception 'Select a segment from the published schedules' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=p_aircraft_type and a."Aircraft_Series_Subtype"=subtype) then raise exception 'Select a configured aircraft subtype matching the segment aircraft type' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=p_aircraft_type and c."Aircraft_Series_Subtype"=subtype and btrim(c."Crew_Code_ID")=crew) then raise exception 'Select a valid crew code' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=p_aircraft_type and p."Aircraft_Series_Subtype"=subtype and btrim(p."Pantry_Code_ID")=pantry) then raise exception 'Select a valid pantry code' using errcode='23503';end if;
 if passenger_basis not in('STANDARD','VARIATION','ACTUAL') or baggage_basis not in('STANDARD','VARIATION','ACTUAL') then raise exception 'Select passenger and baggage weight methods' using errcode='22023';end if;
 if (passenger_basis='VARIATION')<>(passenger_variation is not null) or (baggage_basis='VARIATION')<>(baggage_variation is not null) then raise exception 'Select the required flight variation' using errcode='22023';end if;
 if passenger_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=passenger_variation) then raise exception 'Passenger variation not found' using errcode='23503';end if;
 if baggage_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=baggage_variation) then raise exception 'Baggage variation not found' using errcode='23503';end if;
 if char_length(coalesce(remarks,''))>1000 then raise exception 'Remarks are too long' using errcode='22023';end if;
 insert into "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" as existing("Carrier_IATA","Departure_Airport_IATA","Arrival_Airport_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Updated_By","Updated_At") values(p_iata,p_departure_airport,p_arrival_airport,p_aircraft_type,subtype,crew,pantry,passenger_basis,passenger_variation,baggage_basis,baggage_variation,remarks,auth.uid(),now()) on conflict("Carrier_IATA","Departure_Airport_IATA","Arrival_Airport_IATA","Aircraft_Type_IATA") do update set "Aircraft_Series_Subtype"=excluded."Aircraft_Series_Subtype","Crew_Code_ID"=excluded."Crew_Code_ID","Pantry_Code_ID"=excluded."Pantry_Code_ID","Passenger_Weight_Basis"=excluded."Passenger_Weight_Basis","Passenger_Flight_Variation"=excluded."Passenger_Flight_Variation","Baggage_Weight_Basis"=excluded."Baggage_Weight_Basis","Baggage_Flight_Variation"=excluded."Baggage_Flight_Variation","Remarks"=excluded."Remarks","Updated_By"=auth.uid(),"Updated_At"=now();
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" as existing("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At")
 select l."Schedule_Leg_ID",p_iata,subtype,crew,pantry,passenger_basis,passenger_variation,baggage_basis,baggage_variation,remarks,'SEGMENT_DEFAULT',auth.uid(),now() from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l join "Basic_Carrier_Record"."Flight_Schedule_Imports" i using("Import_ID") where i."Carrier_IATA"=p_iata and i."Status"='PUBLISHED' and btrim(l."Departure_Airport_IATA")=p_departure_airport and btrim(l."Arrival_Airport_IATA")=p_arrival_airport and l."Aircraft_Type_IATA"=p_aircraft_type
 on conflict("Schedule_Leg_ID") do update set "Aircraft_Series_Subtype"=excluded."Aircraft_Series_Subtype","Crew_Code_ID"=excluded."Crew_Code_ID","Pantry_Code_ID"=excluded."Pantry_Code_ID","Passenger_Weight_Basis"=excluded."Passenger_Weight_Basis","Passenger_Flight_Variation"=excluded."Passenger_Flight_Variation","Baggage_Weight_Basis"=excluded."Baggage_Weight_Basis","Baggage_Flight_Variation"=excluded."Baggage_Flight_Variation","Remarks"=excluded."Remarks","Updated_By"=auth.uid(),"Updated_At"=now() where existing."Parameter_Source" in('SEGMENT_DEFAULT','ONLY_CHOICE_DEFAULT');
end $$;

create or replace function "Basic_Carrier_Record".delete_flight_schedule_segment_default(p_iata text,p_departure_airport text,p_arrival_airport text,p_aircraft_type text)
returns void language plpgsql security definer set search_path='' as $$
begin
 p_iata:=upper(btrim(p_iata));p_departure_airport:=upper(btrim(p_departure_airport));p_arrival_airport:=upper(btrim(p_arrival_airport));p_aircraft_type:=upper(btrim(p_aircraft_type));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Flight schedule configuration access denied' using errcode='42501';end if;
 delete from "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p using "Basic_Carrier_Record"."Scheduled_Flight_Legs" l,"Basic_Carrier_Record"."Flight_Schedule_Imports" i where p."Schedule_Leg_ID"=l."Schedule_Leg_ID" and l."Import_ID"=i."Import_ID" and p."Parameter_Source"='SEGMENT_DEFAULT' and i."Carrier_IATA"=p_iata and i."Status"='PUBLISHED' and btrim(l."Departure_Airport_IATA")=p_departure_airport and btrim(l."Arrival_Airport_IATA")=p_arrival_airport and l."Aircraft_Type_IATA"=p_aircraft_type;
 delete from "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" where "Carrier_IATA"=p_iata and "Departure_Airport_IATA"=p_departure_airport and "Arrival_Airport_IATA"=p_arrival_airport and "Aircraft_Type_IATA"=p_aircraft_type;
end $$;

create or replace function private.copy_schedule_parameters_to_new_publication()
returns trigger language plpgsql security definer set search_path='' as $$
declare previous_id uuid;
begin
 if new."Status"<>'PUBLISHED' or old."Status"='PUBLISHED' then return new;end if;
 previous_id:=new."Supersedes_Import_ID";
 if previous_id is null then select "Import_ID" into previous_id from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Carrier_IATA"=new."Carrier_IATA" and "Schedule_Family_ID"=new."Schedule_Family_ID" and "Status"='SUPERSEDED' and "Import_ID"<>new."Import_ID" order by "Superseded_At" desc nulls last limit 1;end if;
 if previous_id is not null then
  insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At")
  select target."Schedule_Leg_ID",new."Carrier_IATA",p."Aircraft_Series_Subtype",p."Crew_Code_ID",p."Pantry_Code_ID",p."Passenger_Weight_Basis",p."Passenger_Flight_Variation",p."Baggage_Weight_Basis",p."Baggage_Flight_Variation",p."Remarks",p."Parameter_Source",new."Published_By",now() from "Basic_Carrier_Record"."Scheduled_Flight_Legs" source join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p on p."Schedule_Leg_ID"=source."Schedule_Leg_ID" join "Basic_Carrier_Record"."Scheduled_Flight_Legs" target on target."Import_ID"=new."Import_ID" and target."Airline_Designator"=source."Airline_Designator" and target."Flight_Number"=source."Flight_Number" and target."Operational_Suffix"=source."Operational_Suffix" and target."Itinerary_Variation_Identifier"=source."Itinerary_Variation_Identifier" and target."Leg_Sequence_Number"=source."Leg_Sequence_Number" and target."Departure_Airport_IATA"=source."Departure_Airport_IATA" and target."Arrival_Airport_IATA"=source."Arrival_Airport_IATA" and target."Aircraft_Type_IATA" is not distinct from source."Aircraft_Type_IATA" where source."Import_ID"=previous_id and p."Parameter_Source"='FLIGHT_OVERRIDE' on conflict("Schedule_Leg_ID") do nothing;
 end if;
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At") select l."Schedule_Leg_ID",new."Carrier_IATA",d."Aircraft_Series_Subtype",d."Crew_Code_ID",d."Pantry_Code_ID",d."Passenger_Weight_Basis",d."Passenger_Flight_Variation",d."Baggage_Weight_Basis",d."Baggage_Flight_Variation",d."Remarks",'SEGMENT_DEFAULT',new."Published_By",now() from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l join "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults" d on d."Carrier_IATA"=new."Carrier_IATA" and d."Departure_Airport_IATA"=l."Departure_Airport_IATA" and d."Arrival_Airport_IATA"=l."Arrival_Airport_IATA" and d."Aircraft_Type_IATA"=l."Aircraft_Type_IATA" where l."Import_ID"=new."Import_ID" on conflict("Schedule_Leg_ID") do nothing;
 perform private.apply_schedule_only_choice_defaults(new."Carrier_IATA",new."Import_ID",new."Published_By");
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
 insert into "Basic_Carrier_Record"."Flight_Schedule_Imports"("Carrier_IATA","Source_Carrier_IATA","Source_Format","Original_File_Name","File_SHA256","File_Size_Bytes","Source_Encoding","Season_Code","Creator_Reference","Coverage_Start_Date","Coverage_End_Date","Status","Total_Record_Count","Accepted_Record_Count","Rejected_Record_Count","Normalized_Leg_Count","Validation_Summary","Uploaded_By","Validated_At","Schedule_Family_ID","Supersedes_Import_ID") values(p_iata,p_iata,'MANUAL',revision_name,hash,1,'UTF-8',source_import."Season_Code",'Revision of '||source_import."Import_ID",source_import."Coverage_Start_Date",source_import."Coverage_End_Date",'VALIDATED',source_import."Normalized_Leg_Count",source_import."Normalized_Leg_Count",0,source_import."Normalized_Leg_Count",jsonb_build_object('valid',true,'source','MANUAL_REVISION','revisionOf',source_import."Import_ID"),auth.uid(),now(),source_import."Schedule_Family_ID",source_import."Import_ID") returning "Import_ID" into new_import_id;
 for source_leg in select * from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Import_ID"=p_source_import_id order by "Source_Line_Number","Schedule_Leg_ID" loop
  line_number:=line_number+1;select * into source_parameters from "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" where "Schedule_Leg_ID"=source_leg."Schedule_Leg_ID";
  parsed:=jsonb_build_object('airlineDesignator',source_leg."Airline_Designator",'flightNumber',source_leg."Flight_Number",'operationalSuffix',source_leg."Operational_Suffix",'itineraryVariation',source_leg."Itinerary_Variation_Identifier",'legSequence',source_leg."Leg_Sequence_Number",'serviceType',source_leg."Service_Type",'periodStart',source_leg."Period_Start_Date",'periodEnd',source_leg."Period_End_Date",'operatingDays',source_leg."Operating_Days"::text,'departureAirport',btrim(source_leg."Departure_Airport_IATA"),'arrivalAirport',btrim(source_leg."Arrival_Airport_IATA"),'departureTime',to_char(source_leg."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(source_leg."Arrival_Time_Local",'HH24:MI'),'arrivalDayOffset',source_leg."Arrival_Day_Offset",'aircraftType',source_leg."Aircraft_Type_IATA",'aircraftSubtype',case when found then source_parameters."Aircraft_Series_Subtype" else null end,'aircraftConfiguration',source_leg."Aircraft_Configuration");
  insert into "Basic_Carrier_Record"."Flight_Schedule_Import_Records"("Import_ID","Carrier_IATA","Line_Number","Record_Type","Raw_Record","Parse_Status","Parsed_Data") values(new_import_id,p_iata,line_number,'M','MANUAL REVISION '||line_number,'PARSED',parsed);
  insert into "Basic_Carrier_Record"."Scheduled_Flight_Legs"("Import_ID","Carrier_IATA","Source_Line_Number","Airline_Designator","Flight_Number","Operational_Suffix","Itinerary_Variation_Identifier","Leg_Sequence_Number","Service_Type","Period_Start_Date","Period_End_Date","Operating_Days","Departure_Airport_IATA","Arrival_Airport_IATA","Departure_Time_Local","Arrival_Time_Local","Arrival_Day_Offset","Departure_UTC_Offset_Minutes","Arrival_UTC_Offset_Minutes","Departure_Terminal","Arrival_Terminal","Aircraft_Type_IATA","Aircraft_Configuration","Traffic_Restriction_Codes","Additional_Data") values(new_import_id,p_iata,line_number,source_leg."Airline_Designator",source_leg."Flight_Number",source_leg."Operational_Suffix",source_leg."Itinerary_Variation_Identifier",source_leg."Leg_Sequence_Number",source_leg."Service_Type",source_leg."Period_Start_Date",source_leg."Period_End_Date",source_leg."Operating_Days",source_leg."Departure_Airport_IATA",source_leg."Arrival_Airport_IATA",source_leg."Departure_Time_Local",source_leg."Arrival_Time_Local",source_leg."Arrival_Day_Offset",source_leg."Departure_UTC_Offset_Minutes",source_leg."Arrival_UTC_Offset_Minutes",source_leg."Departure_Terminal",source_leg."Arrival_Terminal",source_leg."Aircraft_Type_IATA",source_leg."Aircraft_Configuration",source_leg."Traffic_Restriction_Codes",source_leg."Additional_Data"||jsonb_build_object('source','MANUAL_REVISION','revisionOfLegId',source_leg."Schedule_Leg_ID")) returning "Schedule_Leg_ID" into new_leg_id;
  if found and source_parameters."Schedule_Leg_ID" is not null and source_parameters."Parameter_Source"='FLIGHT_OVERRIDE' then insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Parameter_Source","Updated_By","Updated_At") values(new_leg_id,p_iata,source_parameters."Aircraft_Series_Subtype",source_parameters."Crew_Code_ID",source_parameters."Pantry_Code_ID",source_parameters."Passenger_Weight_Basis",source_parameters."Passenger_Flight_Variation",source_parameters."Baggage_Weight_Basis",source_parameters."Baggage_Flight_Variation",source_parameters."Remarks",'FLIGHT_OVERRIDE',auth.uid(),now());end if;
 end loop;
 return new_import_id;
end $$;

with latest_missing_family as(
 select distinct on("Carrier_IATA","Schedule_Family_ID") "Import_ID"
 from "Basic_Carrier_Record"."Flight_Schedule_Imports" i
 where i."Status"='SUPERSEDED' and not exists(select 1 from "Basic_Carrier_Record"."Flight_Schedule_Imports" active where active."Carrier_IATA"=i."Carrier_IATA" and active."Schedule_Family_ID"=i."Schedule_Family_ID" and active."Status"='PUBLISHED')
 order by "Carrier_IATA","Schedule_Family_ID","Published_At" desc nulls last,"Uploaded_At" desc
)
update "Basic_Carrier_Record"."Flight_Schedule_Imports" i set "Status"='PUBLISHED',"Superseded_At"=null where i."Import_ID" in(select "Import_ID" from latest_missing_family);

revoke all on function "Basic_Carrier_Record".cancel_flight_schedule_edition(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".cancel_flight_schedule_edition(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
