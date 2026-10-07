begin;

-- Flight schedules are operational data and therefore have permissions that are
-- independent of carrier and aircraft configuration.
insert into application_security.permissions(permission_code,permission_name,description)
values
  ('FLIGHT_SCHEDULE_VIEW','View flight schedules','View published carrier flight schedules and the daily load-control work list'),
  ('FLIGHT_SCHEDULE_IMPORT','Import flight schedules','Upload and validate IATA SSIM Chapter 7 schedule files'),
  ('FLIGHT_SCHEDULE_PUBLISH','Publish flight schedules','Publish a validated carrier schedule for operational use')
on conflict (permission_code) do update
set permission_name=excluded.permission_name,
    description=excluded.description;

insert into application_security.role_permissions(role_id,permission_id)
select r.role_id,p.permission_id
from application_security.roles r
cross join application_security.permissions p
where r.role_code in ('SOLUTION_ADMINISTRATOR','CARRIER_ADMINISTRATOR','CONFIGURATION_EDITOR')
  and p.permission_code='FLIGHT_SCHEDULE_VIEW'
on conflict do nothing;

insert into application_security.role_permissions(role_id,permission_id)
select r.role_id,p.permission_id
from application_security.roles r
cross join application_security.permissions p
where r.role_code in ('SOLUTION_ADMINISTRATOR','CARRIER_ADMINISTRATOR')
  and p.permission_code in ('FLIGHT_SCHEDULE_IMPORT','FLIGHT_SCHEDULE_PUBLISH')
on conflict do nothing;

create table "Basic_Carrier_Record"."Flight_Schedule_Imports" (
  "Import_ID" uuid primary key default gen_random_uuid(),
  "Carrier_IATA" varchar(2) not null
    references "Basic_Carrier_Record"."MASTER_Carrier_Contact"("Carrier_IATA")
    on update cascade on delete restrict,
  "Source_Carrier_IATA" varchar(2) not null,
  "Source_Format" text not null default 'IATA_SSIM_CHAPTER_7'
    check ("Source_Format"='IATA_SSIM_CHAPTER_7'),
  "Original_File_Name" text not null
    check (char_length(btrim("Original_File_Name")) between 1 and 255 and "Original_File_Name" !~ '[[:cntrl:]]'),
  "File_SHA256" char(64) not null
    check ("File_SHA256" ~ '^[0-9a-f]{64}$'),
  "File_Size_Bytes" bigint not null check ("File_Size_Bytes">0),
  "Source_Encoding" text not null default 'UTF-8'
    check ("Source_Encoding" in ('UTF-8','ISO-8859-1','WINDOWS-1252')),
  "SSIM_Edition" text,
  "Season_Code" varchar(8),
  "Creator_Reference" text,
  "Coverage_Start_Date" date,
  "Coverage_End_Date" date,
  "Status" text not null default 'DRAFT'
    check ("Status" in ('DRAFT','VALIDATED','PUBLISHED','REJECTED','SUPERSEDED')),
  "Total_Record_Count" integer not null default 0 check ("Total_Record_Count">=0),
  "Accepted_Record_Count" integer not null default 0 check ("Accepted_Record_Count">=0),
  "Rejected_Record_Count" integer not null default 0 check ("Rejected_Record_Count">=0),
  "Normalized_Leg_Count" integer not null default 0 check ("Normalized_Leg_Count">=0),
  "Validation_Summary" jsonb not null default '{}'::jsonb
    check (jsonb_typeof("Validation_Summary")='object'),
  "Uploaded_By" uuid not null default auth.uid(),
  "Uploaded_At" timestamptz not null default now(),
  "Validated_At" timestamptz,
  "Published_By" uuid,
  "Published_At" timestamptz,
  "Superseded_At" timestamptz,
  constraint "flight_schedule_import_coverage_check" check (
    ("Coverage_Start_Date" is null and "Coverage_End_Date" is null)
    or ("Coverage_Start_Date" is not null and "Coverage_End_Date">="Coverage_Start_Date")
  ),
  constraint "flight_schedule_import_counts_check" check (
    "Accepted_Record_Count"+"Rejected_Record_Count"<="Total_Record_Count"
  ),
  constraint "flight_schedule_source_carrier_check" check ("Source_Carrier_IATA"="Carrier_IATA"),
  unique ("Import_ID","Carrier_IATA"),
  unique ("Carrier_IATA","File_SHA256")
);

comment on table "Basic_Carrier_Record"."Flight_Schedule_Imports" is
  'Immutable SSIM file editions. Exactly one published edition per carrier supplies the operational daily schedule.';

create unique index "flight_schedule_one_published_import_per_carrier"
  on "Basic_Carrier_Record"."Flight_Schedule_Imports"("Carrier_IATA")
  where "Status"='PUBLISHED';

create index "flight_schedule_imports_carrier_uploaded_idx"
  on "Basic_Carrier_Record"."Flight_Schedule_Imports"("Carrier_IATA","Uploaded_At" desc);

create table "Basic_Carrier_Record"."Flight_Schedule_Import_Records" (
  "Import_ID" uuid not null,
  "Carrier_IATA" varchar(2) not null,
  "Line_Number" integer not null check ("Line_Number">0),
  "Record_Type" varchar(2) not null check (char_length(btrim("Record_Type")) between 1 and 2),
  "Raw_Record" text not null
    check (char_length("Raw_Record") between 1 and 2000 and "Raw_Record" !~ E'[\r\n]'),
  "Parse_Status" text not null
    check ("Parse_Status" in ('PARSED','WARNING','ERROR','SKIPPED')),
  "Validation_Messages" jsonb not null default '[]'::jsonb
    check (jsonb_typeof("Validation_Messages")='array'),
  "Parsed_Data" jsonb not null default '{}'::jsonb
    check (jsonb_typeof("Parsed_Data")='object'),
  primary key ("Import_ID","Line_Number"),
  unique ("Import_ID","Carrier_IATA","Line_Number"),
  constraint "flight_schedule_record_import_fk"
    foreign key ("Import_ID","Carrier_IATA")
    references "Basic_Carrier_Record"."Flight_Schedule_Imports"("Import_ID","Carrier_IATA")
    on update cascade on delete cascade
);

comment on table "Basic_Carrier_Record"."Flight_Schedule_Import_Records" is
  'Every original SSIM line, including headers, trailers, unsupported records and validation errors.';

create table "Basic_Carrier_Record"."Scheduled_Flight_Legs" (
  "Schedule_Leg_ID" uuid primary key default gen_random_uuid(),
  "Import_ID" uuid not null,
  "Carrier_IATA" varchar(2) not null,
  "Source_Line_Number" integer not null,
  "Airline_Designator" varchar(3) not null
    check ("Airline_Designator" ~ '^[A-Z0-9]{2,3}$'),
  "Flight_Number" varchar(4) not null
    check ("Flight_Number" ~ '^(?:[0-9]{1,4}|[0-9]{1,3}[A-Z])$'),
  "Operational_Suffix" varchar(1) not null default '',
  "Itinerary_Variation_Identifier" varchar(8) not null default '1'
    check (char_length(btrim("Itinerary_Variation_Identifier")) between 1 and 8),
  "Leg_Sequence_Number" smallint not null default 1 check ("Leg_Sequence_Number">0),
  "Service_Type" varchar(1) not null check ("Service_Type" ~ '^[A-Z0-9]$'),
  "Period_Start_Date" date not null,
  "Period_End_Date" date not null,
  -- Bits are Monday through Sunday. 1111100 therefore means weekdays.
  "Operating_Days" bit(7) not null,
  "Departure_Airport_IATA" char(3) not null
    check ("Departure_Airport_IATA" ~ '^[A-Z0-9]{3}$'),
  "Arrival_Airport_IATA" char(3) not null
    check ("Arrival_Airport_IATA" ~ '^[A-Z0-9]{3}$'),
  "Departure_Time_Local" time without time zone not null,
  "Arrival_Time_Local" time without time zone not null,
  "Arrival_Day_Offset" smallint not null default 0 check ("Arrival_Day_Offset" between 0 and 2),
  "Departure_UTC_Offset_Minutes" smallint
    check ("Departure_UTC_Offset_Minutes" between -840 and 840),
  "Arrival_UTC_Offset_Minutes" smallint
    check ("Arrival_UTC_Offset_Minutes" between -840 and 840),
  "Departure_Terminal" varchar(8),
  "Arrival_Terminal" varchar(8),
  "Aircraft_Type_IATA" varchar(4)
    check ("Aircraft_Type_IATA" is null or "Aircraft_Type_IATA" ~ '^[A-Z0-9]{2,4}$'),
  "Aircraft_Configuration" varchar(12),
  "Traffic_Restriction_Codes" text,
  "Additional_Data" jsonb not null default '{}'::jsonb
    check (jsonb_typeof("Additional_Data")='object'),
  constraint "scheduled_flight_leg_period_check" check ("Period_End_Date">="Period_Start_Date"),
  constraint "scheduled_flight_leg_route_check" check ("Departure_Airport_IATA"<>"Arrival_Airport_IATA"),
  constraint "scheduled_flight_leg_record_fk"
    foreign key ("Import_ID","Carrier_IATA","Source_Line_Number")
    references "Basic_Carrier_Record"."Flight_Schedule_Import_Records"
      ("Import_ID","Carrier_IATA","Line_Number")
    on update cascade on delete cascade,
  unique (
    "Import_ID","Airline_Designator","Flight_Number","Operational_Suffix",
    "Itinerary_Variation_Identifier","Leg_Sequence_Number","Period_Start_Date",
    "Period_End_Date","Departure_Airport_IATA","Arrival_Airport_IATA"
  )
);

comment on table "Basic_Carrier_Record"."Scheduled_Flight_Legs" is
  'Normalized recurring legs parsed from an SSIM edition. Operating_Days uses ISO weekday order Monday through Sunday.';

create index "scheduled_flight_legs_daily_idx"
  on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
    ("Carrier_IATA","Period_Start_Date","Period_End_Date");
create index "scheduled_flight_legs_departure_idx"
  on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
    ("Carrier_IATA","Departure_Airport_IATA","Period_Start_Date","Period_End_Date");
create index "scheduled_flight_legs_arrival_idx"
  on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
    ("Carrier_IATA","Arrival_Airport_IATA","Period_Start_Date","Period_End_Date");
create index "scheduled_flight_legs_flight_idx"
  on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
    ("Carrier_IATA","Airline_Designator","Flight_Number");
create index "scheduled_flight_legs_source_record_fk_idx"
  on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
    ("Import_ID","Carrier_IATA","Source_Line_Number");

alter table "Basic_Carrier_Record"."Flight_Schedule_Imports" enable row level security;
alter table "Basic_Carrier_Record"."Flight_Schedule_Import_Records" enable row level security;
alter table "Basic_Carrier_Record"."Scheduled_Flight_Legs" enable row level security;

revoke all on "Basic_Carrier_Record"."Flight_Schedule_Imports" from public,anon,authenticated;
revoke all on "Basic_Carrier_Record"."Flight_Schedule_Import_Records" from public,anon,authenticated;
revoke all on "Basic_Carrier_Record"."Scheduled_Flight_Legs" from public,anon,authenticated;
grant select on "Basic_Carrier_Record"."Flight_Schedule_Imports" to authenticated;
grant select on "Basic_Carrier_Record"."Flight_Schedule_Import_Records" to authenticated;
grant select on "Basic_Carrier_Record"."Scheduled_Flight_Legs" to authenticated;

create policy "flight_schedule_import_select"
  on "Basic_Carrier_Record"."Flight_Schedule_Imports"
  for select to authenticated
  using (
    (select private.has_carrier_permission("Carrier_IATA",'FLIGHT_SCHEDULE_VIEW'))
    or (select private.has_global_permission('FLIGHT_SCHEDULE_VIEW'))
  );

create policy "flight_schedule_record_select"
  on "Basic_Carrier_Record"."Flight_Schedule_Import_Records"
  for select to authenticated
  using (
    (select private.has_carrier_permission("Carrier_IATA",'FLIGHT_SCHEDULE_VIEW'))
    or (select private.has_global_permission('FLIGHT_SCHEDULE_VIEW'))
  );

create policy "scheduled_flight_leg_select"
  on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
  for select to authenticated
  using (
    (select private.has_carrier_permission("Carrier_IATA",'FLIGHT_SCHEDULE_VIEW'))
    or (select private.has_global_permission('FLIGHT_SCHEDULE_VIEW'))
  );

create function private.guard_published_schedule_rows()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare import_status text;
begin
  select "Status" into import_status
  from "Basic_Carrier_Record"."Flight_Schedule_Imports"
  where "Import_ID"=coalesce(new."Import_ID",old."Import_ID");
  if import_status in ('PUBLISHED','SUPERSEDED') then
    raise exception 'Published schedule editions are immutable' using errcode='55000';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function private.guard_published_schedule_rows() from public,anon,authenticated;

create trigger "guard_published_schedule_records"
before update or delete on "Basic_Carrier_Record"."Flight_Schedule_Import_Records"
for each row execute function private.guard_published_schedule_rows();

create trigger "guard_published_schedule_legs"
before update or delete on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
for each row execute function private.guard_published_schedule_rows();

create function "Basic_Carrier_Record".create_ssim_schedule_import(
  p_iata text,
  p_source_carrier_iata text,
  p_file_name text,
  p_file_sha256 text,
  p_file_size_bytes bigint,
  p_source_encoding text default 'UTF-8',
  p_ssim_edition text default null,
  p_season_code text default null,
  p_creator_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare new_id uuid;
begin
  p_iata:=upper(btrim(p_iata));
  p_source_carrier_iata:=upper(btrim(p_source_carrier_iata));
  p_file_name:=btrim(p_file_name);
  p_file_sha256:=lower(btrim(p_file_sha256));
  p_source_encoding:=upper(btrim(p_source_encoding));
  if (select auth.uid()) is null or not (
    private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_IMPORT')
    or private.has_global_permission('FLIGHT_SCHEDULE_IMPORT')
  ) then
    raise exception 'Flight schedule import access denied' using errcode='42501';
  end if;
  if not exists (
    select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact"
    where "Carrier_IATA"=p_iata
  ) then
    raise exception 'Carrier not found' using errcode='23503';
  end if;
  if p_file_name='' or char_length(p_file_name)>255 or p_file_name ~ '[[:cntrl:]]'
    or p_source_carrier_iata<>p_iata
    or p_file_sha256 !~ '^[0-9a-f]{64}$' or p_file_size_bytes<=0
    or p_source_encoding not in ('UTF-8','ISO-8859-1','WINDOWS-1252') then
    raise exception 'Invalid SSIM file metadata' using errcode='22023';
  end if;
  insert into "Basic_Carrier_Record"."Flight_Schedule_Imports"(
    "Carrier_IATA","Source_Carrier_IATA","Original_File_Name","File_SHA256","File_Size_Bytes","Source_Encoding",
    "SSIM_Edition","Season_Code","Creator_Reference","Uploaded_By"
  ) values (
    p_iata,p_source_carrier_iata,p_file_name,p_file_sha256,p_file_size_bytes,p_source_encoding,
    nullif(btrim(p_ssim_edition),''),nullif(upper(btrim(p_season_code)),''),
    nullif(btrim(p_creator_reference),''),auth.uid()
  ) returning "Import_ID" into new_id;
  return new_id;
exception when unique_violation then
  raise exception 'This SSIM file has already been uploaded for carrier %',p_iata using errcode='23505';
end;
$$;

create function "Basic_Carrier_Record".stage_ssim_schedule_import(
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

create function "Basic_Carrier_Record".publish_ssim_schedule_import(
  p_iata text,
  p_import_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare target "Basic_Carrier_Record"."Flight_Schedule_Imports"%rowtype;
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not (
    private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_PUBLISH')
    or private.has_global_permission('FLIGHT_SCHEDULE_PUBLISH')
  ) then
    raise exception 'Flight schedule publication access denied' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('published-ssim:'||p_iata,0));
  select * into target
  from "Basic_Carrier_Record"."Flight_Schedule_Imports"
  where "Import_ID"=p_import_id and "Carrier_IATA"=p_iata
  for update;
  if not found then raise exception 'SSIM import not found' using errcode='P0002'; end if;
  if target."Status"<>'VALIDATED' or target."Rejected_Record_Count"<>0
    or target."Normalized_Leg_Count"=0 or target."Coverage_Start_Date" is null then
    raise exception 'Only a completely validated SSIM import can be published' using errcode='55000';
  end if;
  update "Basic_Carrier_Record"."Flight_Schedule_Imports"
  set "Status"='SUPERSEDED',"Superseded_At"=now()
  where "Carrier_IATA"=p_iata and "Status"='PUBLISHED' and "Import_ID"<>p_import_id;
  update "Basic_Carrier_Record"."Flight_Schedule_Imports"
  set "Status"='PUBLISHED',"Published_By"=auth.uid(),"Published_At"=now(),"Superseded_At"=null
  where "Import_ID"=p_import_id;
  return jsonb_build_object(
    'importId',p_import_id,'status','PUBLISHED','carrierIata',p_iata,
    'coverageStart',target."Coverage_Start_Date",'coverageEnd',target."Coverage_End_Date",
    'normalizedLegs',target."Normalized_Leg_Count"
  );
end;
$$;

create function "Basic_Carrier_Record".get_daily_flight_schedule(
  p_iata text,
  p_service_date date,
  p_airport_iata text default null
)
returns table (
  "Schedule_Leg_ID" uuid,
  "Import_ID" uuid,
  "Carrier_IATA" varchar,
  "Service_Date" date,
  "Airline_Designator" varchar,
  "Flight_Number" varchar,
  "Operational_Suffix" varchar,
  "Itinerary_Variation_Identifier" varchar,
  "Leg_Sequence_Number" smallint,
  "Service_Type" varchar,
  "Departure_Airport_IATA" char(3),
  "Arrival_Airport_IATA" char(3),
  "Departure_Local" timestamp without time zone,
  "Arrival_Local" timestamp without time zone,
  "Departure_UTC_Offset_Minutes" smallint,
  "Arrival_UTC_Offset_Minutes" smallint,
  "Departure_Terminal" varchar,
  "Arrival_Terminal" varchar,
  "Aircraft_Type_IATA" varchar,
  "Aircraft_Configuration" varchar,
  "Additional_Data" jsonb
)
language plpgsql
stable
security invoker
set search_path=''
as $$
declare airport text:=nullif(upper(btrim(p_airport_iata)),'');
begin
  p_iata:=upper(btrim(p_iata));
  if (select auth.uid()) is null or not (
    private.has_carrier_permission(p_iata,'FLIGHT_SCHEDULE_VIEW')
    or private.has_global_permission('FLIGHT_SCHEDULE_VIEW')
  ) then
    raise exception 'Flight schedule access denied' using errcode='42501';
  end if;
  if p_service_date is null or (airport is not null and airport !~ '^[A-Z0-9]{3}$') then
    raise exception 'Invalid daily schedule request' using errcode='22023';
  end if;
  return query
  select
    leg."Schedule_Leg_ID",leg."Import_ID",leg."Carrier_IATA",p_service_date,
    leg."Airline_Designator",leg."Flight_Number",leg."Operational_Suffix",
    leg."Itinerary_Variation_Identifier",leg."Leg_Sequence_Number",leg."Service_Type",
    leg."Departure_Airport_IATA",leg."Arrival_Airport_IATA",
    p_service_date+leg."Departure_Time_Local",
    p_service_date+leg."Arrival_Day_Offset"+leg."Arrival_Time_Local",
    leg."Departure_UTC_Offset_Minutes",leg."Arrival_UTC_Offset_Minutes",
    leg."Departure_Terminal",leg."Arrival_Terminal",leg."Aircraft_Type_IATA",
    leg."Aircraft_Configuration",leg."Additional_Data"
  from "Basic_Carrier_Record"."Flight_Schedule_Imports" imp
  join "Basic_Carrier_Record"."Scheduled_Flight_Legs" leg
    on leg."Import_ID"=imp."Import_ID" and leg."Carrier_IATA"=imp."Carrier_IATA"
  where imp."Carrier_IATA"=p_iata
    and imp."Status"='PUBLISHED'
    and p_service_date between leg."Period_Start_Date" and leg."Period_End_Date"
    and get_bit(leg."Operating_Days",extract(isodow from p_service_date)::integer-1)=1
    and (airport is null or airport in (leg."Departure_Airport_IATA",leg."Arrival_Airport_IATA"))
  order by leg."Departure_Time_Local",leg."Airline_Designator",leg."Flight_Number",leg."Leg_Sequence_Number";
end;
$$;

revoke all on function "Basic_Carrier_Record".create_ssim_schedule_import(text,text,text,text,bigint,text,text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".stage_ssim_schedule_import(text,uuid,jsonb,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".publish_ssim_schedule_import(text,uuid) from public,anon;
revoke all on function "Basic_Carrier_Record".get_daily_flight_schedule(text,date,text) from public,anon;
grant execute on function "Basic_Carrier_Record".create_ssim_schedule_import(text,text,text,text,bigint,text,text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".stage_ssim_schedule_import(text,uuid,jsonb,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".publish_ssim_schedule_import(text,uuid) to authenticated;
grant execute on function "Basic_Carrier_Record".get_daily_flight_schedule(text,date,text) to authenticated;

notify pgrst,'reload schema';
commit;
