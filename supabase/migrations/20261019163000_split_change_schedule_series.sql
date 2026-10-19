begin;

alter table "Basic_Carrier_Record"."Scheduled_Flight_Legs"
  drop constraint if exists "Scheduled_Flight_Legs_Import_ID_Airline_Designator_Flight_N_key";

alter table "Basic_Carrier_Record"."Scheduled_Flight_Legs"
  add constraint "Scheduled_Flight_Legs_Series_Slice_key" unique(
    "Import_ID","Airline_Designator","Flight_Number","Operational_Suffix",
    "Itinerary_Variation_Identifier","Leg_Sequence_Number","Period_Start_Date",
    "Period_End_Date","Operating_Days","Departure_Airport_IATA","Arrival_Airport_IATA"
  );

create or replace function "Basic_Carrier_Record".change_manual_schedule_series(
  p_iata text,
  p_import_id uuid,
  p_schedule_leg_id uuid,
  p_selection_start date,
  p_selection_end date,
  p_operating_days text,
  p_action text,
  p_values jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  item "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;
  source_leg "Basic_Carrier_Record"."Scheduled_Flight_Legs"%rowtype;
  source_parameters "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"%rowtype;
  base_values jsonb;
  pieces jsonb:='[]'::jsonb;
  piece jsonb;
  result jsonb;
  residual_days text:='';
  remaining integer;
  old_line integer;
  i integer;
  copy_parameters boolean;
  selected_subtype text;
begin
  p_iata:=upper(btrim(p_iata));
  p_action:=upper(btrim(p_action));
  if (select auth.uid()) is null or not(
    private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE')
    or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')
  ) then raise exception 'Schedule change access denied' using errcode='42501';end if;

  select * into item
  from "Basic_Carrier_Record"."Flight_Schedule_Imports"
  where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata
  for update;
  if not found or item."Source_Format"<>'MANUAL' or item."Status" not in('DRAFT','VALIDATED') then
    raise exception 'Create an editable schedule revision before changing a flight series' using errcode='55000';
  end if;

  select * into source_leg
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs"
  where "Schedule_Leg_ID"=p_schedule_leg_id and "Import_ID"=p_import_id and "Carrier_IATA"=p_iata
  for update;
  if not found then raise exception 'Flight series not found' using errcode='P0002';end if;
  if p_selection_start is null or p_selection_end is null or p_selection_start>p_selection_end
    or p_selection_start<source_leg."Period_Start_Date" or p_selection_end>source_leg."Period_End_Date" then
    raise exception 'The change period must be within the original flight series' using errcode='22023';
  end if;
  if coalesce(p_operating_days,'')!~'^[01]{7}$' or p_operating_days='0000000' then
    raise exception 'Select at least one operating day' using errcode='22023';
  end if;
  if p_action not in('AMEND','CANCEL') or (p_action='AMEND' and p_values is null) then
    raise exception 'Select a valid flight-series action' using errcode='22023';
  end if;
  for i in 1..7 loop
    if substring(p_operating_days,i,1)='1' and substring(source_leg."Operating_Days"::text,i,1)<>'1' then
      raise exception 'A selected day does not operate in the original series' using errcode='22023';
    end if;
    residual_days:=residual_days||case when substring(source_leg."Operating_Days"::text,i,1)='1' and substring(p_operating_days,i,1)='0' then '1' else '0' end;
  end loop;

  base_values:=jsonb_build_object(
    'airlineDesignator',source_leg."Airline_Designator",'flightNumber',source_leg."Flight_Number",
    'operationalSuffix',source_leg."Operational_Suffix",'itineraryVariation',source_leg."Itinerary_Variation_Identifier",
    'legSequence',source_leg."Leg_Sequence_Number",'serviceType',source_leg."Service_Type",
    'departureAirport',btrim(source_leg."Departure_Airport_IATA"),'arrivalAirport',btrim(source_leg."Arrival_Airport_IATA"),
    'departureTime',to_char(source_leg."Departure_Time_Local",'HH24:MI'),'arrivalTime',to_char(source_leg."Arrival_Time_Local",'HH24:MI'),
    'arrivalDayOffset',source_leg."Arrival_Day_Offset",'aircraftType',source_leg."Aircraft_Type_IATA",
    'aircraftSubtype',source_leg."Aircraft_Series_Subtype",'aircraftConfiguration',source_leg."Aircraft_Configuration"
  );
  if p_selection_start>source_leg."Period_Start_Date" then
    pieces:=pieces||jsonb_build_array(jsonb_build_object('copyParameters',true,'values',base_values||jsonb_build_object('periodStart',source_leg."Period_Start_Date",'periodEnd',p_selection_start-1,'operatingDays',source_leg."Operating_Days"::text)));
  end if;
  if residual_days<>'0000000' then
    pieces:=pieces||jsonb_build_array(jsonb_build_object('copyParameters',true,'values',base_values||jsonb_build_object('periodStart',p_selection_start,'periodEnd',p_selection_end,'operatingDays',residual_days)));
  end if;
  if p_action='AMEND' then
    selected_subtype:=upper(btrim(p_values->>'aircraftSubtype'));
    pieces:=pieces||jsonb_build_array(jsonb_build_object('copyParameters',source_leg."Aircraft_Type_IATA"=upper(btrim(p_values->>'aircraftType')) and source_leg."Aircraft_Series_Subtype"=selected_subtype,'values',p_values||jsonb_build_object('periodStart',p_selection_start,'periodEnd',p_selection_end,'operatingDays',p_operating_days)));
  end if;
  if p_selection_end<source_leg."Period_End_Date" then
    pieces:=pieces||jsonb_build_array(jsonb_build_object('copyParameters',true,'values',base_values||jsonb_build_object('periodStart',p_selection_end+1,'periodEnd',source_leg."Period_End_Date",'operatingDays',source_leg."Operating_Days"::text)));
  end if;

  select * into source_parameters from "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters" where "Schedule_Leg_ID"=p_schedule_leg_id;
  old_line:=source_leg."Source_Line_Number";
  delete from "Basic_Carrier_Record"."Flight_Schedule_Import_Records"
  where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata and "Line_Number"=old_line;

  for piece in select value from jsonb_array_elements(pieces) loop
    result:="Basic_Carrier_Record".save_manual_schedule_leg(p_iata,p_import_id,null,piece->'values');
    copy_parameters:=coalesce((piece->>'copyParameters')::boolean,false);
    if copy_parameters and source_parameters."Schedule_Leg_ID" is not null then
      insert into "Basic_Carrier_Record"."Scheduled_Flight_Load_Control_Parameters"(
        "Schedule_Leg_ID","Carrier_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Pantry_Code_ID",
        "Passenger_Weight_Basis","Passenger_Flight_Variation","Baggage_Weight_Basis","Baggage_Flight_Variation",
        "Remarks","Parameter_Source","Updated_By","Updated_At"
      ) values(
        (result->>'scheduleLegId')::uuid,p_iata,source_parameters."Aircraft_Series_Subtype",source_parameters."Crew_Code_ID",source_parameters."Pantry_Code_ID",
        source_parameters."Passenger_Weight_Basis",source_parameters."Passenger_Flight_Variation",source_parameters."Baggage_Weight_Basis",source_parameters."Baggage_Flight_Variation",
        source_parameters."Remarks",source_parameters."Parameter_Source",auth.uid(),now()
      ) on conflict("Schedule_Leg_ID") do nothing;
    end if;
  end loop;

  select count(*) into remaining from "Basic_Carrier_Record"."Scheduled_Flight_Legs" where "Import_ID"=p_import_id;
  update "Basic_Carrier_Record"."Flight_Schedule_Imports" i set
    "Status"=case when remaining>0 then 'VALIDATED' else 'DRAFT' end,
    "Validated_At"=case when remaining>0 then now() else null end,
    "Total_Record_Count"=(select count(*) from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" r where r."Import_ID"=p_import_id),
    "Accepted_Record_Count"=(select count(*) from "Basic_Carrier_Record"."Flight_Schedule_Import_Records" r where r."Import_ID"=p_import_id),
    "Rejected_Record_Count"=0,"Normalized_Leg_Count"=remaining,
    "Coverage_Start_Date"=(select min("Period_Start_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),
    "Coverage_End_Date"=(select max("Period_End_Date") from "Basic_Carrier_Record"."Scheduled_Flight_Legs" l where l."Import_ID"=p_import_id),
    "Validation_Summary"=jsonb_build_object('valid',remaining>0,'source','MANUAL','lastSeriesChange',p_action,'changedAt',now())
  where i."Import_ID"=p_import_id;
  return "Basic_Carrier_Record".get_flight_schedule_edition(p_iata,p_import_id);
end $$;

revoke all on function "Basic_Carrier_Record".change_manual_schedule_series(text,uuid,uuid,date,date,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".change_manual_schedule_series(text,uuid,uuid,date,date,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
