begin;

alter table "Basic_Carrier_Record"."Scheduled_Flight_Legs"
 drop constraint "Scheduled_Flight_Legs_Flight_Number_check",
 add constraint "Scheduled_Flight_Legs_Flight_Number_check"
 check ("Flight_Number" ~ '^(?:[0-9]{1,4}|[0-9]{1,3}[A-Z])$');

create or replace function "Basic_Carrier_Record".stage_ssim_schedule_import(
  p_iata text,
  p_import_id uuid,
  p_records jsonb,
  p_legs jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  record_data jsonb;
  leg_data jsonb;
  import_status text;
  total_count integer;
  accepted_count integer;
  rejected_count integer;
  leg_count integer;
  coverage_start date;
  coverage_end date;
  staged_status text;
  source_line integer;
  operating_days text;
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not (
    private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_IMPORT')
    or private.has_global_permission('FLIGHT_SCHEDULE_IMPORT')
  ) then
    raise exception 'Flight schedule import access denied' using errcode='42501';
  end if;
  if jsonb_typeof(p_records) is distinct from 'array'
    or jsonb_typeof(p_legs) is distinct from 'array'
    or jsonb_array_length(p_records)=0
    or jsonb_array_length(p_records)>1000000
    or jsonb_array_length(p_legs)>500000 then
    raise exception 'Invalid SSIM staging payload' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('ssim-import:'||p_import_id::text,0));
  select "Status" into import_status
  from "Basic_Carrier_Record"."Flight_Schedule_Imports"
  where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata
  for update;
  if not found then raise exception 'SSIM import not found' using errcode='P0002'; end if;
  if import_status not in ('DRAFT','VALIDATED','REJECTED') then
    raise exception 'Only an unpublished SSIM import can be staged' using errcode='55000';
  end if;

  delete from "Basic_Carrier_Record"."Scheduled_Flight_Legs"
  where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata;
  delete from "Basic_Carrier_Record"."Flight_Schedule_Import_Records"
  where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata;

  for record_data in select value from jsonb_array_elements(p_records) loop
    if jsonb_typeof(record_data)<>'object'
      or coalesce(record_data->>'lineNumber','') !~ '^[1-9][0-9]*$'
      or char_length(coalesce(record_data->>'recordType','')) not between 1 and 2
      or char_length(coalesce(record_data->>'rawRecord','')) not between 1 and 2000
      or coalesce(record_data->>'rawRecord','') ~ E'[\r\n]'
      or coalesce(record_data->>'parseStatus','') not in ('PARSED','WARNING','ERROR','SKIPPED')
      or jsonb_typeof(coalesce(record_data->'validationMessages','[]'::jsonb))<>'array'
      or jsonb_typeof(coalesce(record_data->'parsedData','{}'::jsonb))<>'object' then
      raise exception 'Invalid SSIM record staging row' using errcode='22023';
    end if;
    insert into "Basic_Carrier_Record"."Flight_Schedule_Import_Records"(
      "Import_ID","Carrier_IATA","Line_Number","Record_Type","Raw_Record","Parse_Status",
      "Validation_Messages","Parsed_Data"
    ) values (
      p_import_id,p_iata,(record_data->>'lineNumber')::integer,upper(btrim(record_data->>'recordType')),
      record_data->>'rawRecord',record_data->>'parseStatus',
      coalesce(record_data->'validationMessages','[]'::jsonb),coalesce(record_data->'parsedData','{}'::jsonb)
    );
  end loop;

  for leg_data in select value from jsonb_array_elements(p_legs) loop
    if jsonb_typeof(leg_data)<>'object'
      or coalesce(leg_data->>'sourceLineNumber','') !~ '^[1-9][0-9]*$'
      or upper(btrim(coalesce(leg_data->>'airlineDesignator',''))) !~ '^[A-Z0-9]{2,3}$'
      or btrim(coalesce(leg_data->>'flightNumber','')) !~ '^(?:[0-9]{1,4}|[0-9]{1,3}[A-Z])$'
      or upper(btrim(coalesce(leg_data->>'serviceType',''))) !~ '^[A-Z0-9]$'
      or upper(btrim(coalesce(leg_data->>'departureAirport',''))) !~ '^[A-Z0-9]{3}$'
      or upper(btrim(coalesce(leg_data->>'arrivalAirport',''))) !~ '^[A-Z0-9]{3}$'
      or upper(btrim(leg_data->>'departureAirport'))=upper(btrim(leg_data->>'arrivalAirport'))
      or coalesce(leg_data->>'operatingDays','') !~ '^[01]{7}$'
      or jsonb_typeof(coalesce(leg_data->'additionalData','{}'::jsonb))<>'object' then
      raise exception 'Invalid normalized SSIM leg' using errcode='22023';
    end if;
    source_line:=(leg_data->>'sourceLineNumber')::integer;
    operating_days:=leg_data->>'operatingDays';
    insert into "Basic_Carrier_Record"."Scheduled_Flight_Legs"(
      "Import_ID","Carrier_IATA","Source_Line_Number","Airline_Designator","Flight_Number",
      "Operational_Suffix","Itinerary_Variation_Identifier","Leg_Sequence_Number","Service_Type",
      "Period_Start_Date","Period_End_Date","Operating_Days","Departure_Airport_IATA",
      "Arrival_Airport_IATA","Departure_Time_Local","Arrival_Time_Local","Arrival_Day_Offset",
      "Departure_UTC_Offset_Minutes","Arrival_UTC_Offset_Minutes","Departure_Terminal",
      "Arrival_Terminal","Aircraft_Type_IATA","Aircraft_Configuration",
      "Traffic_Restriction_Codes","Additional_Data"
    ) values (
      p_import_id,p_iata,source_line,upper(btrim(leg_data->>'airlineDesignator')),
      btrim(leg_data->>'flightNumber'),coalesce(nullif(upper(btrim(leg_data->>'operationalSuffix')),''),''),
      coalesce(nullif(btrim(leg_data->>'itineraryVariationIdentifier'),''),'1'),
      coalesce((leg_data->>'legSequenceNumber')::smallint,1),upper(btrim(leg_data->>'serviceType')),
      (leg_data->>'periodStart')::date,(leg_data->>'periodEnd')::date,operating_days::bit(7),
      upper(btrim(leg_data->>'departureAirport')),upper(btrim(leg_data->>'arrivalAirport')),
      (leg_data->>'departureTimeLocal')::time,(leg_data->>'arrivalTimeLocal')::time,
      coalesce((leg_data->>'arrivalDayOffset')::smallint,0),
      nullif(leg_data->>'departureUtcOffsetMinutes','')::smallint,
      nullif(leg_data->>'arrivalUtcOffsetMinutes','')::smallint,
      nullif(upper(btrim(leg_data->>'departureTerminal')),''),
      nullif(upper(btrim(leg_data->>'arrivalTerminal')),''),
      nullif(upper(btrim(leg_data->>'aircraftTypeIata')),''),
      nullif(upper(btrim(leg_data->>'aircraftConfiguration')),''),
      nullif(upper(btrim(leg_data->>'trafficRestrictionCodes')),''),
      coalesce(leg_data->'additionalData','{}'::jsonb)
    );
  end loop;

  select count(*),count(*) filter(where "Parse_Status"<>'ERROR'),count(*) filter(where "Parse_Status"='ERROR')
  into total_count,accepted_count,rejected_count
  from "Basic_Carrier_Record"."Flight_Schedule_Import_Records"
  where "Import_ID"=p_import_id;
  select count(*),min("Period_Start_Date"),max("Period_End_Date")
  into leg_count,coverage_start,coverage_end
  from "Basic_Carrier_Record"."Scheduled_Flight_Legs"
  where "Import_ID"=p_import_id;
  staged_status:=case when rejected_count=0 and leg_count>0 then 'VALIDATED' else 'REJECTED' end;
  update "Basic_Carrier_Record"."Flight_Schedule_Imports"
  set "Status"=staged_status,
      "Coverage_Start_Date"=coverage_start,
      "Coverage_End_Date"=coverage_end,
      "Total_Record_Count"=total_count,
      "Accepted_Record_Count"=accepted_count,
      "Rejected_Record_Count"=rejected_count,
      "Normalized_Leg_Count"=leg_count,
      "Validation_Summary"=jsonb_build_object(
        'valid',staged_status='VALIDATED','records',total_count,'accepted',accepted_count,
        'rejected',rejected_count,'normalizedLegs',leg_count
      ),
      "Validated_At"=case when staged_status='VALIDATED' then now() else null end
  where "Import_ID"=p_import_id;
  return jsonb_build_object(
    'importId',p_import_id,'status',staged_status,'records',total_count,'accepted',accepted_count,
    'rejected',rejected_count,'normalizedLegs',leg_count,'coverageStart',coverage_start,
    'coverageEnd',coverage_end
  );
end;
$$;

create or replace function "Basic_Carrier_Record".save_manual_schedule_leg(p_iata text,p_import_id uuid,p_schedule_leg_id uuid,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare status text;source_format text;leg_id uuid:=p_schedule_leg_id;line_no integer;airline text;flight text;suffix text;variation text;leg_sequence smallint;service text;period_start date;period_end date;days text;departure text;arrival text;departure_time time;arrival_time time;arrival_day smallint;aircraft_type text;aircraft_configuration text;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_CONFIGURE') or private.has_global_permission('FLIGHT_SCHEDULE_CONFIGURE')) then raise exception 'Manual schedule access denied' using errcode='42501';end if;
 select "Status","Source_Format" into status,source_format from "Basic_Carrier_Record"."Flight_Schedule_Imports" where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata for update;
 if not found or source_format<>'MANUAL' or status not in('DRAFT','VALIDATED') then raise exception 'Editable manual schedule not found' using errcode='55000';end if;
 airline:=upper(btrim(coalesce(p_values->>'airlineDesignator',p_iata)));flight:=btrim(p_values->>'flightNumber');suffix:=upper(btrim(coalesce(p_values->>'operationalSuffix','')));variation:=upper(btrim(coalesce(p_values->>'itineraryVariation','01')));leg_sequence:=(p_values->>'legSequence')::smallint;service:=upper(btrim(p_values->>'serviceType'));period_start:=(p_values->>'periodStart')::date;period_end:=(p_values->>'periodEnd')::date;days:=p_values->>'operatingDays';departure:=upper(btrim(p_values->>'departureAirport'));arrival:=upper(btrim(p_values->>'arrivalAirport'));departure_time:=(p_values->>'departureTime')::time;arrival_time:=(p_values->>'arrivalTime')::time;arrival_day:=(p_values->>'arrivalDayOffset')::smallint;aircraft_type:=upper(btrim(p_values->>'aircraftType'));aircraft_configuration:=nullif(upper(btrim(p_values->>'aircraftConfiguration')),'');
 if airline<>p_iata or flight!~'^(?:[0-9]{1,4}|[0-9]{1,3}[A-Z])$' or suffix!~'^[A-Z0-9]?$' or variation!~'^[A-Z0-9]{1,8}$' or leg_sequence not between 1 and 99 or service!~'^[A-Z0-9]$' or period_end<period_start or days!~'^[01]{7}$' or days='0000000' or departure!~'^[A-Z0-9]{3}$' or arrival!~'^[A-Z0-9]{3}$' or departure=arrival or arrival_day not between 0 and 2 or aircraft_type!~'^[A-Z0-9]{2,4}$' or char_length(coalesce(aircraft_configuration,''))>12 then raise exception 'Check every manual schedule value' using errcode='22023';end if;
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

notify pgrst,'reload schema';
commit;
