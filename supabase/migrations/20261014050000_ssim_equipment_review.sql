begin;

create or replace function private.default_schedule_leg_equipment()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new."Aircraft_Type_IATA" is null then return new;end if;
  if new."Aircraft_Series_Subtype" is null then
    select min(a."Aircraft_Series_Subtype")
    into new."Aircraft_Series_Subtype"
    from "Basic_Carrier_Record"."Basic_Aircraft_Data" a
    where a."Carrier_IATA"=new."Carrier_IATA"
      and a."Aircraft_Type_IATA"=new."Aircraft_Type_IATA"
    having count(distinct a."Aircraft_Series_Subtype")=1;
  end if;
  if new."Aircraft_Series_Subtype" is not null
    and (new."Aircraft_Configuration" is null or upper(btrim(new."Aircraft_Configuration"))='XX') then
    select min(btrim(c."Configuration_Code"))
    into new."Aircraft_Configuration"
    from "Basic_Carrier_Record"."Aircraft_Configurations" c
    where c."Carrier_IATA"=new."Carrier_IATA"
      and c."Aircraft_Type_IATA"=new."Aircraft_Type_IATA"
      and c."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype"
      and c."Is_Default";
  end if;
  return new;
end;
$$;

revoke all on function private.default_schedule_leg_equipment() from public,anon,authenticated;

drop trigger if exists "default_schedule_leg_equipment" on "Basic_Carrier_Record"."Scheduled_Flight_Legs";
create trigger "default_schedule_leg_equipment"
before insert on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
for each row execute function private.default_schedule_leg_equipment();

with resolved as (
  select l."Schedule_Leg_ID",min(a."Aircraft_Series_Subtype") subtype
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l
  join "Basic_Carrier_Record"."Flight_Schedule_Imports" i on i."Import_ID"=l."Import_ID"
  join "Basic_Carrier_Record"."Basic_Aircraft_Data" a
    on a."Carrier_IATA"=l."Carrier_IATA" and a."Aircraft_Type_IATA"=l."Aircraft_Type_IATA"
  where l."Aircraft_Series_Subtype" is null and i."Source_Format"<>'MANUAL' and i."Status"='VALIDATED'
  group by l."Schedule_Leg_ID"
  having count(distinct a."Aircraft_Series_Subtype")=1
)
update "Basic_Carrier_Record"."Scheduled_Flight_Legs" l
set "Aircraft_Series_Subtype"=resolved.subtype
from resolved
where l."Schedule_Leg_ID"=resolved."Schedule_Leg_ID";

with defaults as (
  select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",min(btrim("Configuration_Code")) configuration_code
  from "Basic_Carrier_Record"."Aircraft_Configurations"
  where "Is_Default"
  group by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"
)
update "Basic_Carrier_Record"."Scheduled_Flight_Legs" l
set "Aircraft_Configuration"=defaults.configuration_code
from "Basic_Carrier_Record"."Flight_Schedule_Imports" i,defaults
where i."Import_ID"=l."Import_ID" and i."Source_Format"<>'MANUAL' and i."Status"='VALIDATED'
  and l."Aircraft_Series_Subtype" is not null
  and (l."Aircraft_Configuration" is null or upper(btrim(l."Aircraft_Configuration"))='XX')
  and defaults."Carrier_IATA"=l."Carrier_IATA"
  and defaults."Aircraft_Type_IATA"=l."Aircraft_Type_IATA"
  and defaults."Aircraft_Series_Subtype"=l."Aircraft_Series_Subtype";

update "Basic_Carrier_Record"."Flight_Schedule_Imports"
set "Validation_Summary"=coalesce("Validation_Summary",'{}'::jsonb)||jsonb_build_object('equipmentReviewConfirmed',false)
where "Source_Format"<>'MANUAL' and "Status"='VALIDATED';

create or replace function "Basic_Carrier_Record".get_flight_schedule_edition(p_iata text,p_import_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;can_view boolean;can_configure boolean;can_review boolean;
begin
 p_iata:=upper(btrim(p_iata));
 can_view:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW') or private.has_global_permission('FLIGHT_SCHEDULE_VIEW'));
 can_configure:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE'));
 can_review:=(select auth.uid()) is not null and (can_configure or private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_IMPORT') or private.has_global_permission('FLIGHT_SCHEDULE_IMPORT'));
 if not can_view then raise exception 'Flight schedule access denied' using errcode='42501';end if;
 select * into item from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata;
 if not found then raise exception 'Schedule edition not found' using errcode='P0002';end if;
 return jsonb_build_object(
  'importId',item."Import_ID",'name',item."Original_File_Name",'sourceFormat',item."Source_Format",'status',item."Status",'seasonCode',item."Season_Code",
  'coverageStart',item."Coverage_Start_Date",'coverageEnd',item."Coverage_End_Date",'recordCount',item."Total_Record_Count",'legCount',item."Normalized_Leg_Count",'rejectedCount',item."Rejected_Record_Count",
  'canEdit',can_configure and item."Source_Format"='MANUAL' and item."Status" in('DRAFT','VALIDATED'),'canDelete',can_configure and item."Status"<>'PUBLISHED',
  'canReviewEquipment',can_review and item."Source_Format"<>'MANUAL' and item."Status"='VALIDATED',
  'equipmentReviewComplete',item."Source_Format"='MANUAL' or coalesce(item."Validation_Summary"->>'equipmentReviewConfirmed','false')='true',
  'legs',coalesce((select jsonb_agg(jsonb_build_object(
    'scheduleLegId',l."Schedule_Leg_ID",'flightNumber',l."Flight_Number",'operationalSuffix',l."Operational_Suffix",'itineraryVariation',l."Itinerary_Variation_Identifier",
    'legSequence',l."Leg_Sequence_Number",'serviceType',l."Service_Type",'periodStart',l."Period_Start_Date",'periodEnd',l."Period_End_Date",'operatingDays',l."Operating_Days"::text,
    'departureAirport',btrim(l."Departure_Airport_IATA"),'arrivalAirport',btrim(l."Arrival_Airport_IATA"),'departureTime',to_char(l."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(l."Arrival_Time_Local",'HH24:MI'),
    'arrivalDayOffset',l."Arrival_Day_Offset",'aircraftType',l."Aircraft_Type_IATA",'aircraftSubtype',l."Aircraft_Series_Subtype",'aircraftConfiguration',l."Aircraft_Configuration"
  ) order by l."Flight_Number",l."Itinerary_Variation_Identifier",l."Leg_Sequence_Number",l."Period_Start_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=item."Import_ID"),'[]'::jsonb)
 );
end $$;

create or replace function "Basic_Carrier_Record".save_ssim_schedule_equipment_review(p_iata text,p_import_id uuid,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;choice jsonb;aircraft_type text;aircraft_subtype text;aircraft_configuration text;seen text[]:='{}';expected_types integer;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(
   private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')
   or private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_IMPORT') or private.has_global_permission('FLIGHT_SCHEDULE_IMPORT')
 ) then raise exception 'SSIM equipment review access denied' using errcode='42501';end if;
 select * into item from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata for update;
 if not found then raise exception 'Schedule edition not found' using errcode='P0002';end if;
 if item."Source_Format"='MANUAL' or item."Status"<>'VALIDATED' then raise exception 'Only a validated SSIM edition can be reviewed' using errcode='55000';end if;
 if jsonb_typeof(p_values) is distinct from 'array' or jsonb_array_length(p_values)=0 then raise exception 'Review every SSIM aircraft type before publication' using errcode='22023';end if;
 select count(distinct "Aircraft_Type_IATA") into expected_types from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Import_ID"=p_import_id and "Aircraft_Type_IATA" is not null;
 if expected_types<>jsonb_array_length(p_values) or exists(select 1 from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Import_ID"=p_import_id and "Aircraft_Type_IATA" is null) then raise exception 'Review every SSIM aircraft type before publication' using errcode='22023';end if;
 for choice in select value from jsonb_array_elements(p_values) loop
  aircraft_type:=upper(btrim(choice->>'aircraftType'));aircraft_subtype:=upper(btrim(choice->>'aircraftSubtype'));aircraft_configuration:=nullif(upper(btrim(choice->>'aircraftConfiguration')),'');
  if aircraft_type!~'^[A-Z0-9]{2,4}$' or aircraft_subtype!~'^[A-Z0-9]{1,4}$' or aircraft_type=any(seen) then raise exception 'Select each configured SSIM aircraft type once' using errcode='22023';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Import_ID"=p_import_id and "Aircraft_Type_IATA"=aircraft_type) then raise exception 'The reviewed aircraft type is not present in this SSIM edition' using errcode='23503';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=aircraft_type and a."Aircraft_Series_Subtype"=aircraft_subtype) then raise exception 'Select an aircraft type configured for this carrier' using errcode='23503';end if;
  if exists(select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=aircraft_type and c."Aircraft_Series_Subtype"=aircraft_subtype) and (aircraft_configuration is null or not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=aircraft_type and c."Aircraft_Series_Subtype"=aircraft_subtype and btrim(c."Configuration_Code")=aircraft_configuration)) then raise exception 'Select a cabin configuration from the matching AHM565 D9 page' using errcode='23503';end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=aircraft_type and c."Aircraft_Series_Subtype"=aircraft_subtype) then aircraft_configuration:=null;end if;
  update "Basic_Carrier_Record"."Scheduled_Flight_Legs"
  set "Aircraft_Series_Subtype"=aircraft_subtype,"Aircraft_Configuration"=aircraft_configuration,
      "Additional_Data"=coalesce("Additional_Data",'{}'::jsonb)||jsonb_build_object('equipmentReview',jsonb_build_object('aircraftSubtype',aircraft_subtype,'aircraftConfiguration',aircraft_configuration,'confirmedAt',now()))
  where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=aircraft_type;
  seen:=array_append(seen,aircraft_type);
 end loop;
 update "Basic_Carrier_Record"."Flight_Schedule_Imports"
 set "Validation_Summary"=coalesce("Validation_Summary",'{}'::jsonb)||jsonb_build_object('equipmentReviewConfirmed',true,'equipmentReviewConfirmedAt',now(),'equipmentReviewConfirmedBy',auth.uid())
 where "Import_ID"=p_import_id;
 return "Basic_Carrier_Record".get_flight_schedule_edition(p_iata,p_import_id);
end $$;

create or replace function "Basic_Carrier_Record".publish_ssim_schedule_import(p_iata text,p_import_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_PUBLISH') or private.has_global_permission('FLIGHT_SCHEDULE_PUBLISH')) then raise exception 'Flight schedule publication access denied' using errcode='42501';end if;
 select * into target from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata for update;
 if not found then raise exception 'Schedule edition not found' using errcode='P0002';end if;
 if target."Status"<>'VALIDATED' or target."Rejected_Record_Count"<>0 or target."Normalized_Leg_Count"=0 or target."Coverage_Start_Date" is null then raise exception 'Only a completely validated schedule edition can be published' using errcode='55000';end if;
 if target."Source_Format"<>'MANUAL' and coalesce(target."Validation_Summary"->>'equipmentReviewConfirmed','false')<>'true' then raise exception 'Review and confirm the SSIM aircraft type and D9 cabin configuration before publication' using errcode='55000';end if;
 if exists(
  select 1 from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l
  where l."Import_ID"=p_import_id and (l."Aircraft_Type_IATA" is null or l."Aircraft_Series_Subtype" is null or (
    exists(select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=l."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=l."Aircraft_Series_Subtype")
    and (l."Aircraft_Configuration" is null or not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=l."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=l."Aircraft_Series_Subtype" and btrim(c."Configuration_Code")=btrim(l."Aircraft_Configuration")))
  ))
 ) then raise exception 'The SSIM equipment review is incomplete' using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('published-schedule-family:'||p_iata||':'||target."Schedule_Family_ID",0));
 update "Basic_Carrier_Record"."Flight_Schedule_Imports" set "Status"='SUPERSEDED',"Superseded_At"=now() where "Carrier_IATA"=p_iata and "Schedule_Family_ID"=target."Schedule_Family_ID" and "Status"='PUBLISHED' and "Import_ID"<>p_import_id;
 update "Basic_Carrier_Record"."Flight_Schedule_Imports" set "Status"='PUBLISHED',"Published_By"=auth.uid(),"Published_At"=now(),"Superseded_At"=null,"Cancelled_By"=null,"Cancelled_At"=null where "Import_ID"=p_import_id;
 return jsonb_build_object('importId',p_import_id,'status','PUBLISHED','carrierIata',p_iata,'coverageStart',target."Coverage_Start_Date",'coverageEnd',target."Coverage_End_Date",'normalizedLegs',target."Normalized_Leg_Count");
end $$;

revoke all on function "Basic_Carrier_Record".save_ssim_schedule_equipment_review(text,uuid,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_ssim_schedule_equipment_review(text,uuid,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
