begin;

insert into application_security.permissions(permission_code,permission_name,description)
values('FLIGHT_SCHEDULE_CONFIGURE','Configure flight schedules','Add Load Control defaults to published schedule legs and maintain manual schedule editions')
on conflict(permission_code) do update set permission_name=excluded.permission_name,description=excluded.description;

insert into application_security.role_permissions(role_id,permission_id)
select r.role_id,p.permission_id from application_security.roles r cross join application_security.permissions p
where r.role_code in('SOLUTION_ADMINISTRATOR','CARRIER_ADMINISTRATOR') and p.permission_code='FLIGHT_SCHEDULE_CONFIGURE'
on conflict do nothing;

alter table "Basic_Carrier_Record"."Flight_Schedule_Imports"
  drop constraint if exists "Flight_Schedule_Imports_Source_Format_check";
alter table "Basic_Carrier_Record"."Flight_Schedule_Imports"
  add constraint "Flight_Schedule_Imports_Source_Format_check"
  check("Source_Format" in('IATA_SSIM_CHAPTER_7','MANUAL'));

create table "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"(
  "Schedule_Leg_ID" uuid primary key references "Basic_Carrier_Record"."Scheduled_Flight_Legs"("Schedule_Leg_ID") on delete cascade,
  "Carrier_IATA" varchar(2) not null references "Basic_Carrier_Record"."MASTER_Carrier_Contact"("Carrier_IATA") on update cascade on delete restrict,
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
  constraint "Scheduled_Flight_Load_Control_Parameters_passenger_check" check(
    ("Passenger_Weight_Basis"='VARIATION' and "Passenger_Flight_Variation" is not null)
    or ("Passenger_Weight_Basis"<>'VARIATION' and "Passenger_Flight_Variation" is null)
  ),
  constraint "Scheduled_Flight_Load_Control_Parameters_baggage_check" check(
    ("Baggage_Weight_Basis"='VARIATION' and "Baggage_Flight_Variation" is not null)
    or ("Baggage_Weight_Basis"<>'VARIATION' and "Baggage_Flight_Variation" is null)
  ),
  constraint "Scheduled_Flight_Load_Control_Parameters_remarks_check" check(char_length(coalesce("Remarks",''))<=1000),
  unique("Schedule_Leg_ID","Carrier_IATA")
);

create index "schedule_load_control_parameters_carrier_idx"
  on "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Carrier_IATA");
alter table "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" enable row level security;
revoke all on "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" from public,anon,authenticated;
grant select on "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" to authenticated;
create policy "schedule_load_control_parameters_select"
  on "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" for select to authenticated
  using((select private.has_carrier_permission("Carrier_IATA",'FLIGHT_SCHEDULE_VIEW')) or (select private.has_global_permission('FLIGHT_SCHEDULE_VIEW')));

create function "Basic_Carrier_Record".get_flight_schedule_workspace(p_iata text)
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
    'aircraftType',l."Aircraft_Type_IATA",'aircraftConfiguration',l."Aircraft_Configuration",
    'parameters',case when p."Schedule_Leg_ID" is null then null else jsonb_build_object(
      'aircraftSubtype',p."Aircraft_Series_Subtype",'crewCode',btrim(p."Crew_Code_ID"),'pantryCode',btrim(p."Pantry_Code_ID"),
      'passengerWeightBasis',p."Passenger_Weight_Basis",'passengerVariation',p."Passenger_Flight_Variation",
      'baggageWeightBasis',p."Baggage_Weight_Basis",'baggageVariation',p."Baggage_Flight_Variation",'remarks',coalesce(p."Remarks",'')) end
  ) order by l."Flight_Number",l."Itinerary_Variation_Identifier",l."Leg_Sequence_Number",l."Period_Start_Date")
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l left join "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" p using("Schedule_Leg_ID") where l."Import_ID"=published_id),'[]'::jsonb),
  'aircraft',coalesce((select jsonb_agg(jsonb_build_object('typeCode',a."Aircraft_Type_IATA",'subtype',a."Aircraft_Series_Subtype",'name',btrim(a."Aircraft_Type")) order by a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype") from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata),'[]'::jsonb),
  'crewCodes',coalesce((select jsonb_agg(jsonb_build_object('typeCode',x."Aircraft_Type_IATA",'subtype',x."Aircraft_Series_Subtype",'code',x."Crew_Code_ID") order by x."Aircraft_Type_IATA",x."Aircraft_Series_Subtype",x."Crew_Code_ID") from(select distinct "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Crew_Code_ID") "Crew_Code_ID" from "Basic_Carrier_Record"."Aircraft_Crew_Codes" where "Carrier_IATA"=p_iata)x),'[]'::jsonb),
  'pantryCodes',coalesce((select jsonb_agg(jsonb_build_object('typeCode',x."Aircraft_Type_IATA",'subtype',x."Aircraft_Series_Subtype",'code',x."Pantry_Code_ID") order by x."Aircraft_Type_IATA",x."Aircraft_Series_Subtype",x."Pantry_Code_ID") from(select distinct "Aircraft_Type_IATA","Aircraft_Series_Subtype",btrim("Pantry_Code_ID") "Pantry_Code_ID" from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" where "Carrier_IATA"=p_iata)x),'[]'::jsonb),
  'variations',coalesce((select jsonb_agg(jsonb_build_object('code',"Flight_Type_Variation",'description',"Flight_Type_Variation_Description") order by "Flight_Type_Variation") from "Basic_Carrier_Record"."Carrier_Flight_Variations" where "Carrier_IATA"=p_iata),'[]'::jsonb)
 ) into payload;
 return payload;
end $$;

create function "Basic_Carrier_Record".save_flight_schedule_leg_parameters(p_iata text,p_schedule_leg_id uuid,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare leg "Basic_Carrier_Record"."Scheduled_Flight_Legs"%rowtype;subtype text;crew text;pantry text;passenger_basis text;passenger_variation text;baggage_basis text;baggage_variation text;remarks text;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Flight schedule configuration access denied' using errcode='42501';end if;
 select l.* into leg from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l join "Basic_Carrier_Record"."Flight_Schedule_Imports" i using("Import_ID") where l."Schedule_Leg_ID"=p_schedule_leg_id and l."Carrier_IATA"=p_iata and i."Status"='PUBLISHED';
 if not found then raise exception 'Published schedule leg not found' using errcode='P0002';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Load Control parameters are required' using errcode='22023';end if;
 subtype:=upper(btrim(p_values->>'aircraftSubtype'));crew:=upper(btrim(p_values->>'crewCode'));pantry:=upper(btrim(p_values->>'pantryCode'));
 passenger_basis:=upper(btrim(p_values->>'passengerWeightBasis'));passenger_variation:=nullif(upper(btrim(p_values->>'passengerVariation')),'');
 baggage_basis:=upper(btrim(p_values->>'baggageWeightBasis'));baggage_variation:=nullif(upper(btrim(p_values->>'baggageVariation')),'');remarks:=nullif(btrim(p_values->>'remarks'),'');
 if leg."Aircraft_Type_IATA" is null or not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=leg."Aircraft_Type_IATA" and a."Aircraft_Series_Subtype"=subtype) then raise exception 'Select a configured aircraft subtype matching the scheduled aircraft type' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=leg."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=subtype and btrim(c."Crew_Code_ID")=crew) then raise exception 'Select a valid crew code' using errcode='23503';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=leg."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=subtype and btrim(p."Pantry_Code_ID")=pantry) then raise exception 'Select a valid pantry code' using errcode='23503';end if;
 if passenger_basis not in('STANDARD','VARIATION','ACTUAL') or baggage_basis not in('STANDARD','VARIATION','ACTUAL') then raise exception 'Select passenger and baggage weight methods' using errcode='22023';end if;
 if (passenger_basis='VARIATION')<>(passenger_variation is not null) or (baggage_basis='VARIATION')<>(baggage_variation is not null) then raise exception 'Select the required flight variation' using errcode='22023';end if;
 if (passenger_variation is not null or baggage_variation is not null) and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=coalesce(passenger_variation,baggage_variation)) then raise exception 'Flight variation not found' using errcode='23503';end if;
 if passenger_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=passenger_variation) then raise exception 'Passenger variation not found' using errcode='23503';end if;
 if baggage_variation is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" v where v."Carrier_IATA"=p_iata and v."Flight_Type_Variation"=baggage_variation) then raise exception 'Baggage variation not found' using errcode='23503';end if;
 if char_length(coalesce(remarks,''))>1000 then raise exception 'Remarks are too long' using errcode='22023';end if;
 insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"("Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID","Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation","Remarks","Updated_By","Updated_At")
 values(p_schedule_leg_id,p_iata,subtype,crew,pantry,passenger_basis,passenger_variation,baggage_basis,baggage_variation,remarks,auth.uid(),now())
 on conflict("Schedule_Leg_ID") do update set "Aircraft_Series_Subtype"=excluded."Aircraft_Series_Subtype","Crew_Code_ID"=excluded."Crew_Code_ID","Pantry_Code_ID"=excluded."Pantry_Code_ID","Passenger_Weight_Basis"=excluded."Passenger_Weight_Basis","Passenger_Flight_Variation"=excluded."Passenger_Flight_Variation","Baggage_Weight_Basis"=excluded."Baggage_Weight_Basis","Baggage_Flight_Variation"=excluded."Baggage_Flight_Variation","Remarks"=excluded."Remarks","Updated_By"=auth.uid(),"Updated_At"=now();
 return "Basic_Carrier_Record".get_flight_schedule_workspace(p_iata);
end $$;

create function "Basic_Carrier_Record".create_manual_schedule_import(p_iata text,p_name text,p_season_code text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare new_id uuid;hash text;
begin
 p_iata:=upper(btrim(p_iata));p_name:=btrim(p_name);
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Manual schedule access denied' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata) or char_length(p_name) not between 1 and 120 then raise exception 'Invalid manual schedule name' using errcode='22023';end if;
 hash:=md5(gen_random_uuid()::text||clock_timestamp()::text)||md5(gen_random_uuid()::text||p_iata);
 insert into "Basic_Carrier_Record"."Flight_Schedule_Imports"("Carrier_IATA","Source_Carrier_IATA","Source_Format","Original_File_Name","File_SHA256","File_Size_Bytes","Source_Encoding","Season_Code","Creator_Reference","Status","Uploaded_By")
 values(p_iata,p_iata,'MANUAL',p_name,hash,1,'UTF-8',nullif(upper(btrim(p_season_code)),''),'Manual data entry','DRAFT',auth.uid()) returning "Import_ID" into new_id;
 return new_id;
end $$;

create function "Basic_Carrier_Record".save_manual_schedule_leg(p_iata text,p_import_id uuid,p_schedule_leg_id uuid,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare status text;source_format text;leg_id uuid:=p_schedule_leg_id;line_no integer;airline text;flight text;suffix text;variation text;leg_sequence smallint;service text;period_start date;period_end date;days text;departure text;arrival text;departure_time time;arrival_time time;arrival_day smallint;aircraft_type text;aircraft_configuration text;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Manual schedule access denied' using errcode='42501';end if;
 select "Status","Source_Format" into status,source_format from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata for update;
 if not found or source_format<>'MANUAL' or status not in('DRAFT','VALIDATED') then raise exception 'Editable manual schedule not found' using errcode='55000';end if;
 airline:=upper(btrim(coalesce(p_values->>'airlineDesignator',p_iata)));flight:=btrim(p_values->>'flightNumber');suffix:=upper(btrim(coalesce(p_values->>'operationalSuffix','')));variation:=upper(btrim(coalesce(p_values->>'itineraryVariation','01')));leg_sequence:=(p_values->>'legSequence')::smallint;service:=upper(btrim(p_values->>'serviceType'));period_start:=(p_values->>'periodStart')::date;period_end:=(p_values->>'periodEnd')::date;days:=p_values->>'operatingDays';departure:=upper(btrim(p_values->>'departureAirport'));arrival:=upper(btrim(p_values->>'arrivalAirport'));departure_time:=(p_values->>'departureTime')::time;arrival_time:=(p_values->>'arrivalTime')::time;arrival_day:=(p_values->>'arrivalDayOffset')::smallint;aircraft_type:=upper(btrim(p_values->>'aircraftType'));aircraft_configuration:=nullif(upper(btrim(p_values->>'aircraftConfiguration')),'');
 if airline<>p_iata or flight!~'^[0-9]{1,4}$' or suffix!~'^[A-Z0-9]?$' or variation!~'^[A-Z0-9]{1,8}$' or leg_sequence not between 1 and 99 or service!~'^[A-Z0-9]$' or period_end<period_start or days!~'^[01]{7}$' or days='0000000' or departure!~'^[A-Z0-9]{3}$' or arrival!~'^[A-Z0-9]{3}$' or departure=arrival or arrival_day not between 0 and 2 or aircraft_type!~'^[A-Z0-9]{2,4}$' or char_length(coalesce(aircraft_configuration,''))>12 then raise exception 'Check every manual schedule value' using errcode='22023';end if;
 if leg_id is null then
  select coalesce(max("Line_Number"),0)+1 into line_no from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" where "Import_ID"=p_import_id;
  insert into "Basic_Carrier_Record"."Flight_Schedule_Import_Records"("Import_ID","Carrier_IATA","Line_Number","Record_Type","Raw_Record","Parse_Status","Parsed_Data") values(p_import_id,p_iata,line_no,'M','MANUAL ENTRY '||line_no,'PARSED',p_values);
  insert into "Basic_Carrier_Record"."Scheduled_Flight_Legs"("Import_ID","Carrier_IATA","Source_Line_Number","Airline_Designator","Flight_Number","Operational_Suffix","Itinerary_Variation_Identifier","Leg_Sequence_Number","Service_Type","Period_Start_Date","Period_End_Date","Operating_Days","Departure_Airport_IATA","Arrival_Airport_IATA","Departure_Time_Local","Arrival_Time_Local","Arrival_Day_Offset","Aircraft_Type_IATA","Aircraft_Configuration","Additional_Data") values(p_import_id,p_iata,line_no,airline,flight,suffix,variation,leg_sequence,service,period_start,period_end,days::bit(7),departure,arrival,departure_time,arrival_time,arrival_day,aircraft_type,aircraft_configuration,jsonb_build_object('source','MANUAL')) returning "Schedule_Leg_ID" into leg_id;
 else
  select "Source_Line_Number" into line_no from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Schedule_Leg_ID"=leg_id and "Import_ID"=p_import_id and "Carrier_IATA"=p_iata;
  if not found then raise exception 'Manual schedule leg not found' using errcode='P0002';end if;
  update "Basic_Carrier_Record"."Scheduled_Flight_Legs" set "Airline_Designator"=airline,"Flight_Number"=flight,"Operational_Suffix"=suffix,"Itinerary_Variation_Identifier"=variation,"Leg_Sequence_Number"=leg_sequence,"Service_Type"=service,"Period_Start_Date"=period_start,"Period_End_Date"=period_end,"Operating_Days"=days::bit(7),"Departure_Airport_IATA"=departure,"Arrival_Airport_IATA"=arrival,"Departure_Time_Local"=departure_time,"Arrival_Time_Local"=arrival_time,"Arrival_Day_Offset"=arrival_day,"Aircraft_Type_IATA"=aircraft_type,"Aircraft_Configuration"=aircraft_configuration where "Schedule_Leg_ID"=leg_id;
  update "Basic_Carrier_Record"."Flight_Schedule_Import_Records" set "Parsed_Data"=p_values where "Import_ID"=p_import_id and "Line_Number"=line_no;
 end if;
 update "Basic_Carrier_Record"."Flight_Schedule_Imports" i set "Status"='VALIDATED',"Validated_At"=now(),"Total_Record_Count"=(select count(*) from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" r where r."Import_ID"=p_import_id),"Accepted_Record_Count"=(select count(*) from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" r where r."Import_ID"=p_import_id),"Rejected_Record_Count"=0,"Normalized_Leg_Count"=(select count(*) from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),"Coverage_Start_Date"=(select min("Period_Start_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),"Coverage_End_Date"=(select max("Period_End_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),"Validation_Summary"=jsonb_build_object('valid',true,'source','MANUAL') where i."Import_ID"=p_import_id;
 return jsonb_build_object('importId',p_import_id,'scheduleLegId',leg_id,'status','VALIDATED');
end $$;

revoke all on function "Basic_Carrier_Record".get_flight_schedule_workspace(text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_flight_schedule_leg_parameters(text,uuid,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".create_manual_schedule_import(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_manual_schedule_leg(text,uuid,uuid,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_flight_schedule_workspace(text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_flight_schedule_leg_parameters(text,uuid,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".create_manual_schedule_import(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_manual_schedule_leg(text,uuid,uuid,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
