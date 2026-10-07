begin;

create function "Basic_Carrier_Record".get_flight_schedule_edition(p_iata text,p_import_id uuid)
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
  'canEdit',can_configure and item."Source_Format"='MANUAL' and item."Status" in('DRAFT','VALIDATED'),
  'canDelete',can_configure and item."Status"<>'PUBLISHED',
  'legs',coalesce((select jsonb_agg(jsonb_build_object(
    'scheduleLegId',l."Schedule_Leg_ID",'flightNumber',l."Flight_Number",'operationalSuffix',l."Operational_Suffix",'itineraryVariation',l."Itinerary_Variation_Identifier",
    'legSequence',l."Leg_Sequence_Number",'serviceType',l."Service_Type",'periodStart',l."Period_Start_Date",'periodEnd',l."Period_End_Date",'operatingDays',l."Operating_Days"::text,
    'departureAirport',btrim(l."Departure_Airport_IATA"),'arrivalAirport',btrim(l."Arrival_Airport_IATA"),'departureTime',to_char(l."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(l."Arrival_Time_Local",'HH24:MI'),
    'arrivalDayOffset',l."Arrival_Day_Offset",'aircraftType',l."Aircraft_Type_IATA",'aircraftConfiguration',l."Aircraft_Configuration"
  ) order by l."Flight_Number",l."Itinerary_Variation_Identifier",l."Leg_Sequence_Number",l."Period_Start_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=item."Import_ID"),'[]'::jsonb)
 );
end $$;

create function "Basic_Carrier_Record".delete_manual_schedule_leg(p_iata text,p_import_id uuid,p_schedule_leg_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;line_no integer;remaining integer;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Manual schedule access denied' using errcode='42501';end if;
 select * into item from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata for update;
 if not found or item."Source_Format"<>'MANUAL' or item."Status" not in('DRAFT','VALIDATED') then raise exception 'Editable manual schedule not found' using errcode='55000';end if;
 delete from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Schedule_Leg_ID"=p_schedule_leg_id and "Import_ID"=p_import_id and "Carrier_IATA"=p_iata returning "Source_Line_Number" into line_no;
 if not found then raise exception 'Manual schedule leg not found' using errcode='P0002';end if;
 delete from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata and "Line_Number"=line_no;
 select count(*) into remaining from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Import_ID"=p_import_id;
 update "Basic_Carrier_Record"."Flight_Schedule_Imports" i set "Status"=case when remaining>0 then 'VALIDATED' else 'DRAFT' end,"Validated_At"=case when remaining>0 then now() else null end,
  "Total_Record_Count"=(select count(*) from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" r where r."Import_ID"=p_import_id),
  "Accepted_Record_Count"=(select count(*) from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" r where r."Import_ID"=p_import_id),"Rejected_Record_Count"=0,"Normalized_Leg_Count"=remaining,
  "Coverage_Start_Date"=(select min("Period_Start_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),
  "Coverage_End_Date"=(select max("Period_End_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),
  "Validation_Summary"=jsonb_build_object('valid',remaining>0,'source','MANUAL') where i."Import_ID"=p_import_id;
 return "Basic_Carrier_Record".get_flight_schedule_edition(p_iata,p_import_id);
end $$;

create function "Basic_Carrier_Record".delete_flight_schedule_edition(p_iata text,p_import_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare edition_status text;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Schedule deletion access denied' using errcode='42501';end if;
 select "Status" into edition_status from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata for update;
 if not found then raise exception 'Schedule edition not found' using errcode='P0002';end if;
 if edition_status='PUBLISHED' then raise exception 'The published schedule cannot be deleted. Publish a replacement edition first.' using errcode='55000';end if;
 delete from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata;
 return true;
end $$;

revoke all on function "Basic_Carrier_Record".get_flight_schedule_edition(text,uuid) from public,anon;
revoke all on function "Basic_Carrier_Record".delete_manual_schedule_leg(text,uuid,uuid) from public,anon;
revoke all on function "Basic_Carrier_Record".delete_flight_schedule_edition(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_flight_schedule_edition(text,uuid) to authenticated;
grant execute on function "Basic_Carrier_Record".delete_manual_schedule_leg(text,uuid,uuid) to authenticated;
grant execute on function "Basic_Carrier_Record".delete_flight_schedule_edition(text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
