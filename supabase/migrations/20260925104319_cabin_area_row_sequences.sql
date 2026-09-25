begin;
alter table "Basic_Carrier_Record"."Aircraft_Cabin_Areas" add column "Row_Sequence" integer[];
comment on column "Basic_Carrier_Record"."Aircraft_Cabin_Areas"."Row_Sequence" is 'Optional explicit row identifiers in forward-to-aft order. NULL uses the existing inclusive range. Range columns retain numeric bounds for compatibility.';
create function private.cabin_row_numbers(p_sequence integer[],p_from integer,p_to integer) returns integer[] language sql immutable set search_path='' as $$
 select coalesce(p_sequence,array(select generate_series(p_from,p_to)));
$$;
create function private.valid_cabin_row_sequence(p_sequence integer[]) returns boolean language sql immutable set search_path='' as $$
 select p_sequence is null or (cardinality(p_sequence)>0 and cardinality(p_sequence)<=99 and array_ndims(p_sequence)=1 and not exists(select 1 from unnest(p_sequence) n where n is null or n<1 or n>99) and cardinality(p_sequence)=(select count(distinct n) from unnest(p_sequence) n));
$$;
revoke all on function private.cabin_row_numbers(integer[],integer,integer),private.valid_cabin_row_sequence(integer[]) from public,anon;
grant execute on function private.cabin_row_numbers(integer[],integer,integer),private.valid_cabin_row_sequence(integer[]) to authenticated;
alter table "Basic_Carrier_Record"."Aircraft_Cabin_Areas" add constraint "Aircraft_Cabin_Areas_Row_Sequence_check" check(private.valid_cabin_row_sequence("Row_Sequence"));

CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".get_aircraft_d5(p_iata text, p_type_code text, p_subtype text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');excluded jsonb;areas jsonb;flight jsonb;cabin jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg("Seat_Row_Number" order by "Seat_Row_Number"),'[]') into excluded from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'rowSequence',to_jsonb("Row_Sequence"),'deck',btrim("Cabin_Area_Deck"),'startRow',"Cabin_Area_Start_Row",'endRow',"Cabin_Area_End_Row",'centroid',"Cabin_Area_BA_Centroid",'startArm',"Cabin_Area_BA_Start",'endArm',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by btrim("Cabin_Area_ID")),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Location_Short_Form_ID"),'description',btrim("Location_Description"),'seats',"Location_No_Of_Seats",'centroid',"Location_BA_Centroid",'index',"Location_Index_Per_Weight_Unit") order by btrim("Location_Short_Form_ID")),'[]') into flight from "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Location_Short_Form_ID"),'description',btrim("Location_Description"),'seats',"Location_No_Of_Seats",'centroid',"Location_BA_Centroid",'index',"Location_Index_Per_Weight_Unit") order by btrim("Location_Short_Form_ID")),'[]') into cabin from "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((excluded||areas||flight||cabin)::text),'typeCode',tc,'subtype',st,'excludedRows',excluded,'cabinAreas',areas,'flightDeckLocations',flight,'cabinCrewLocations',cabin);
end $function$
;
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".get_aircraft_d8(p_iata text, p_type_code text, p_subtype text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');excluded jsonb;areas jsonb;rows jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg("Seat_Row_Number" order by "Seat_Row_Number"),'[]') into excluded from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'rowSequence',to_jsonb("Row_Sequence"),'rowFrom',"Cabin_Area_Start_Row",'rowTo',"Cabin_Area_End_Row",'seatGrouping',"Seat_Grouping_Default") order by "Cabin_Area_Start_Row"),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim(r."Seat_Row_Cabin_Area"),'rowNumber',btrim(r."Seat_Row_Number")::integer,'maximumSeats',r."Seat_Row_Seats",'maximumWeight',r."Seat_Row_Max_Weight",'centroid',r."Seat_Row_BA",'index',r."Seat_Row_Index_Per_Weight_Unit",'seatGroupingOverride',r."Seat_Grouping_Override") order by btrim(r."Seat_Row_Number")::integer),'[]') into rows from "Basic_Carrier_Record"."Aircraft_Seat_Rows" r where r."Carrier_IATA"=p_iata and r."Aircraft_Type_IATA"=tc and r."Aircraft_Series_Subtype"=st and exists(select 1 from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" a where a."Carrier_IATA"=r."Carrier_IATA" and a."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and a."Aircraft_Series_Subtype"=r."Aircraft_Series_Subtype" and a."Cabin_Area_ID"=r."Seat_Row_Cabin_Area" and btrim(r."Seat_Row_Number")::integer=any(private.cabin_row_numbers(a."Row_Sequence",a."Cabin_Area_Start_Row",a."Cabin_Area_End_Row"))) and not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" e where e."Carrier_IATA"=r."Carrier_IATA" and e."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and e."Aircraft_Series_Subtype"=r."Aircraft_Series_Subtype" and e."Seat_Row_Number"=btrim(r."Seat_Row_Number")::integer);
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((excluded||areas||rows)::text),'typeCode',tc,'subtype',st,'excludedRows',excluded,'cabinAreas',areas,'rows',rows);
end $function$
;
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".get_aircraft_d9(p_iata text, p_type_code text, p_subtype text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');excluded jsonb;areas jsonb;classes jsonb;configs jsonb:='[]';physical jsonb;cfg record;rows jsonb;
begin if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select coalesce(jsonb_agg("Seat_Row_Number" order by "Seat_Row_Number"),'[]') into excluded from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'rowSequence',to_jsonb("Row_Sequence"),'rowFrom',"Cabin_Area_Start_Row",'rowTo',"Cabin_Area_End_Row",'centroid',"Cabin_Area_BA_Centroid",'from',"Cabin_Area_BA_Start",'to',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by "Cabin_Area_Start_Row"),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_build_array(jsonb_build_object('slot',1,'code',btrim("Carrier_Class_1_Code"),'name',btrim("Carrier_Class_1_Name")),jsonb_build_object('slot',2,'code',btrim("Carrier_Class_2_Code"),'name',btrim("Carrier_Class_2_Name")),jsonb_build_object('slot',3,'code',btrim("Carrier_Class_3_Code"),'name',btrim("Carrier_Class_3_Name")),jsonb_build_object('slot',4,'code',btrim("Carrier_Class_4_Code"),'name',btrim("Carrier_Class_4_Name"))),'[]') into classes from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"=p_iata;
 select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim(r."Seat_Row_Cabin_Area"),'rowNumber',btrim(r."Seat_Row_Number")::integer,'maximumSeats',r."Seat_Row_Seats",'grouping',coalesce(r."Seat_Grouping_Override",a."Seat_Grouping_Default")) order by btrim(r."Seat_Row_Number")::integer),'[]') into physical
 from "Basic_Carrier_Record"."Aircraft_Seat_Rows" r join "Basic_Carrier_Record"."Aircraft_Cabin_Areas" a on a."Carrier_IATA"=r."Carrier_IATA" and a."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and a."Aircraft_Series_Subtype"=r."Aircraft_Series_Subtype" and a."Cabin_Area_ID"=r."Seat_Row_Cabin_Area"
 where r."Carrier_IATA"=p_iata and r."Aircraft_Type_IATA"=tc and r."Aircraft_Series_Subtype"=st
 and btrim(r."Seat_Row_Number")::integer=any(private.cabin_row_numbers(a."Row_Sequence",a."Cabin_Area_Start_Row",a."Cabin_Area_End_Row")) and not excluded @> jsonb_build_array(btrim(r."Seat_Row_Number")::integer);
 for cfg in select btrim("Configuration_Code") code,min(btrim("Configuration_Code_Description")) description from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st group by btrim("Configuration_Code") order by 1 loop
  select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim("Cabin_Area_ID"),'classSeats',jsonb_build_array("Seat_Class_Code_1",coalesce("Seat_Class_Code_2",0),coalesce("Seat_Class_Code_3",0),coalesce("Seat_Class_Code_4",0)),'blockedRows',to_jsonb("Blocked_Centre_Rows"),'totalSeats',"Total_Seats_Cabin_Area_ID",'centroid',"Cabin_Area_BA_Centroid",'from',"Cabin_Area_BA_Start",'to',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by btrim("Cabin_Area_ID")),'[]') into rows from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Configuration_Code")=cfg.code;
  configs:=configs||jsonb_build_array(jsonb_build_object('code',cfg.code,'description',cfg.description,'rows',rows));end loop;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((excluded||areas||classes||configs||physical)::text),'typeCode',tc,'subtype',st,'excludedRows',excluded,'cabinAreas',areas,'classes',classes,'seatRows',physical,'configurations',configs);end $function$
;
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".save_aircraft_d5(p_iata text, p_type_code text, p_subtype text, p_revision text, p_section text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;row_number integer;groupings jsonb;sequence_rows integer[];occupied integer[]:=array[]::integer[];members integer[];
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;

 -- Serialise D5 and D8 saves before checking the revision.
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
 if "Basic_Carrier_Record".get_aircraft_d5(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if jsonb_typeof(p_rows)<>'array' or (p_section<>'excludedRows' and jsonb_array_length(p_rows)<1) then raise exception 'At least one row required' using errcode='22023';end if;
 if p_section='excludedRows' then
  delete from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  for item in select value from jsonb_array_elements(p_rows) loop
   row_number:=(item #>> '{}')::integer;
   insert into "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Seat_Row_Number") values(p_iata,tc,st,row_number);
  end loop;
  delete from "Basic_Carrier_Record"."Aircraft_Seat_Rows" r using "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" e
   where r."Carrier_IATA"=p_iata and r."Aircraft_Type_IATA"=tc and r."Aircraft_Series_Subtype"=st
    and e."Carrier_IATA"=r."Carrier_IATA" and e."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and e."Aircraft_Series_Subtype"=r."Aircraft_Series_Subtype"
    and e."Seat_Row_Number"=btrim(r."Seat_Row_Number")::integer;
 elsif p_section='cabinAreas' then
  for item in select value from jsonb_array_elements(p_rows) loop
   if item ? 'rowSequence' and item->'rowSequence'<>'null'::jsonb then
    if jsonb_typeof(item->'rowSequence') is distinct from 'array' then raise exception 'Invalid row sequence' using errcode='23514';end if;
    sequence_rows:=array(select value::integer from jsonb_array_elements_text(item->'rowSequence'));
   else sequence_rows:=null;end if;
   if not private.valid_cabin_row_sequence(sequence_rows) then raise exception 'Invalid row sequence' using errcode='23514';end if;
   if sequence_rows is not null and ((item->>'startRow')::integer is distinct from (select min(n) from unnest(sequence_rows) n) or (item->>'endRow')::integer is distinct from (select max(n) from unnest(sequence_rows) n)) then raise exception 'Sequence bounds mismatch' using errcode='23514';end if;
   members:=private.cabin_row_numbers(sequence_rows,(item->>'startRow')::integer,(item->>'endRow')::integer);
   if cardinality(members)=0 or members && occupied then raise exception 'Cabin Area rows overlap or are empty' using errcode='23514';end if;
   occupied:=occupied||members;
  end loop;

  select coalesce(jsonb_object_agg(btrim("Cabin_Area_ID"),"Seat_Grouping_Default"),'{}') into groupings from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  delete from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st
   and btrim("Cabin_Area_ID") not in (select upper(btrim(value->>'id')) from jsonb_array_elements(p_rows));
  for item in select value from jsonb_array_elements(p_rows) loop insert into "Basic_Carrier_Record"."Aircraft_Cabin_Areas"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Cabin_Area_ID","Cabin_Area_Deck","Cabin_Area_Start_Row","Cabin_Area_End_Row","Cabin_Area_BA_Centroid","Cabin_Area_BA_Start","Cabin_Area_BA_End","Cabin_Area_Index_Per_Weight_Unit","Seat_Grouping_Default","Row_Sequence") values(p_iata,tc,st,upper(btrim(item->>'id')),upper(btrim(item->>'deck')),(item->>'startRow')::integer,(item->>'endRow')::integer,(item->>'centroid')::double precision,(item->>'startArm')::double precision,(item->>'endArm')::double precision,(item->>'index')::double precision,groupings->>upper(btrim(item->>'id')),case when jsonb_typeof(item->'rowSequence')='array' then array(select value::integer from jsonb_array_elements_text(item->'rowSequence')) else null end)
  on conflict ("Carrier_IATA","Aircraft_Type_IATA","Cabin_Area_ID","Aircraft_Series_Subtype") do update set
   "Row_Sequence"=excluded."Row_Sequence",
   "Cabin_Area_Deck"=excluded."Cabin_Area_Deck",
   "Cabin_Area_Start_Row"=excluded."Cabin_Area_Start_Row",
   "Cabin_Area_End_Row"=excluded."Cabin_Area_End_Row",
   "Cabin_Area_BA_Centroid"=excluded."Cabin_Area_BA_Centroid",
   "Cabin_Area_BA_Start"=excluded."Cabin_Area_BA_Start",
   "Cabin_Area_BA_End"=excluded."Cabin_Area_BA_End",
   "Cabin_Area_Index_Per_Weight_Unit"=excluded."Cabin_Area_Index_Per_Weight_Unit";
  end loop;
 elsif p_section in('flightDeckLocations','cabinCrewLocations') then
  if p_section='flightDeckLocations' then delete from "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;else delete from "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;end if;
  for item in select value from jsonb_array_elements(p_rows) loop
   if p_section='flightDeckLocations' then insert into "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Location_Short_Form_ID","Location_Description","Location_No_Of_Seats","Location_BA_Centroid","Location_Index_Per_Weight_Unit") values(p_iata,tc,st,upper(btrim(item->>'id')),btrim(item->>'description'),(item->>'seats')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision);
   else insert into "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Location_Short_Form_ID","Location_Description","Location_No_Of_Seats","Location_BA_Centroid","Location_Index_Per_Weight_Unit") values(p_iata,tc,st,upper(btrim(item->>'id')),btrim(item->>'description'),(item->>'seats')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision);end if;
  end loop;
 else raise exception 'Unknown section' using errcode='22023';end if;
 if p_section in ('cabinAreas','excludedRows') then
  if exists(select 1 from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" e where e."Carrier_IATA"=p_iata and e."Aircraft_Type_IATA"=tc and e."Aircraft_Series_Subtype"=st and not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st and e."Seat_Row_Number"=any(private.cabin_row_numbers(a."Row_Sequence",a."Cabin_Area_Start_Row",a."Cabin_Area_End_Row")))) then raise exception 'Excluded row outside cabin areas' using errcode='23514';end if;
  if exists(select 1 from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st and not exists(select 1 from unnest(private.cabin_row_numbers(a."Row_Sequence",a."Cabin_Area_Start_Row",a."Cabin_Area_End_Row")) n where not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" e where e."Carrier_IATA"=p_iata and e."Aircraft_Type_IATA"=tc and e."Aircraft_Series_Subtype"=st and e."Seat_Row_Number"=n))) then raise exception 'Cabin area must retain a row' using errcode='23514';end if;
 end if;
 return "Basic_Carrier_Record".get_aircraft_d5(p_iata,tc,st);
end $function$
;
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".save_aircraft_d8(p_iata text, p_type_code text, p_subtype text, p_revision text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;area_row record;payload_rows jsonb;groupings jsonb;entry record;v_grouping text;old_overrides jsonb;legacy boolean;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;

 -- Serialise D5 and D8 saves before checking the revision.
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
 if "Basic_Carrier_Record".get_aircraft_d8(p_iata,tc,st)->>'revision'is distinct from p_revision then raise exception 'Conflict' using errcode='40001';end if;
 legacy:=jsonb_typeof(p_rows)='array';
 payload_rows:=case when legacy then p_rows else p_rows->'rows' end;
 groupings:=case when legacy then '{}'::jsonb else p_rows->'areaGroupings' end;
 if jsonb_typeof(groupings) is distinct from 'object' then raise exception 'Invalid area groupings' using errcode='22023';end if;
 for entry in select * from jsonb_each(groupings) loop
  if jsonb_typeof(entry.value) not in ('string','null') then raise exception 'Invalid grouping' using errcode='22023';end if;
  update "Basic_Carrier_Record"."Aircraft_Cabin_Areas" set "Seat_Grouping_Default"=nullif(btrim(entry.value #>> '{}'),'') where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Cabin_Area_ID")=entry.key;
  if not found then raise exception 'Unknown cabin area' using errcode='23514';end if;
 end loop;
 select coalesce(jsonb_object_agg(btrim("Seat_Row_Number"),"Seat_Grouping_Override"),'{}') into old_overrides from "Basic_Carrier_Record"."Aircraft_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if jsonb_typeof(payload_rows) is distinct from 'array' or jsonb_array_length(payload_rows)<1 then raise exception 'At least one complete row required' using errcode='22023';end if;
 delete from "Basic_Carrier_Record"."Aircraft_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 for item in select value from jsonb_array_elements(payload_rows) loop
  if exists(select 1 from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Seat_Row_Number"=(item->>'rowNumber')::integer) then raise exception 'Excluded seat row' using errcode='23514';end if;
  select "Row_Sequence" as row_sequence,"Cabin_Area_Start_Row" as row_from,"Cabin_Area_End_Row" as row_to,"Seat_Grouping_Default" as seat_grouping into area_row from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Cabin_Area_ID")=btrim(item->>'areaId');
  if not found or not ((item->>'rowNumber')::integer=any(private.cabin_row_numbers(area_row.row_sequence,area_row.row_from,area_row.row_to))) then raise exception 'Seat row outside cabin area' using errcode='23514';end if;
  v_grouping:=case when legacy then old_overrides->>(item->>'rowNumber') else nullif(btrim(item->>'seatGroupingOverride'),'') end;
  if private.d8_grouping_seats(coalesce(v_grouping,area_row.seat_grouping)) is distinct from null
     and private.d8_grouping_seats(coalesce(v_grouping,area_row.seat_grouping))<>(item->>'maximumSeats')::integer then
   raise exception 'Seat grouping does not match row seats' using errcode='23514';
  end if;
  insert into "Basic_Carrier_Record"."Aircraft_Seat_Rows"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Seat_Row_Number","Seat_Row_Cabin_Area","Seat_Row_Seats","Seat_Row_Max_Weight","Seat_Row_BA","Seat_Row_Index_Per_Weight_Unit","Seat_Grouping_Override") values(p_iata,tc,st,(item->>'rowNumber')::integer::text,btrim(item->>'areaId'),(item->>'maximumSeats')::integer,case when item->'maximumWeight'='null'::jsonb then null else (item->>'maximumWeight')::integer end,(item->>'centroid')::double precision,(item->>'index')::double precision,v_grouping);
 end loop;
 return "Basic_Carrier_Record".get_aircraft_d8(p_iata,tc,st);
end $function$
;
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".save_aircraft_d9(p_iata text, p_type_code text, p_subtype text, p_revision text, p_original_code text, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 tc text:=upper(btrim(p_type_code));
 st text:=upper(btrim(p_subtype));
 code text:=upper(btrim(p_values->>'code'));
 description text:=btrim(p_values->>'description');
 item jsonb;
 current_data jsonb;
 blocked integer[];
 physical jsonb;
 usable integer;
 expected integer;
 available integer;
BEGIN
 IF NOT (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') OR private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) THEN
  RAISE EXCEPTION 'Not authorised' USING errcode='42501';
 END IF;
 PERFORM 1 FROM "Basic_Carrier_Record"."Basic_Aircraft_Data" WHERE "Carrier_IATA"=p_iata AND "Aircraft_Type_IATA"=tc AND "Aircraft_Series_Subtype"=st FOR UPDATE;
 current_data:="Basic_Carrier_Record".get_aircraft_d9(p_iata,tc,st);
 IF code IS NULL OR code !~ '^[A-Z]$' THEN RAISE EXCEPTION 'Configuration Code must be one letter' USING errcode='23514'; END IF;
 IF current_data->>'revision' IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Conflict' USING errcode='40001'; END IF;
 IF jsonb_typeof(p_values->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(p_values->'rows')<1 THEN RAISE EXCEPTION 'Rows required' USING errcode='22023'; END IF;
 IF p_original_code IS NOT NULL THEN
  DELETE FROM "Basic_Carrier_Record"."Aircraft_Configurations" WHERE "Carrier_IATA"=p_iata AND "Aircraft_Type_IATA"=tc AND "Aircraft_Series_Subtype"=st AND btrim("Configuration_Code")=upper(btrim(p_original_code));
 END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_values->'rows') LOOP
  IF jsonb_typeof(coalesce(item->'blockedRows','[]'::jsonb)) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid blocked rows' USING errcode='23514'; END IF;
  blocked:=ARRAY(SELECT value::integer FROM jsonb_array_elements_text(coalesce(item->'blockedRows','[]'::jsonb)));
  IF cardinality(blocked)<>(SELECT count(DISTINCT n) FROM unnest(blocked) n) THEN RAISE EXCEPTION 'Duplicate blocked row' USING errcode='23514'; END IF;
  SELECT coalesce(jsonb_agg(r),'[]'::jsonb) INTO physical FROM jsonb_array_elements(current_data->'seatRows') r WHERE r->>'areaId'=item->>'areaId';
  IF EXISTS(SELECT 1 FROM unnest(blocked) n WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(physical) r WHERE (r->>'rowNumber')::integer=n AND r->>'grouping' ~ '^3(-3){0,3}$')) THEN
   RAISE EXCEPTION 'Blocked row requires physical three-seat groups on D8' USING errcode='23514';
  END IF;
  SELECT count(*) INTO expected FROM jsonb_array_elements(current_data->'cabinAreas') a CROSS JOIN LATERAL unnest(private.cabin_row_numbers(case when jsonb_typeof(a->'rowSequence')='array' then array(select value::integer from jsonb_array_elements_text(a->'rowSequence')) else null end,(a->>'rowFrom')::integer,(a->>'rowTo')::integer)) n WHERE a->>'id'=item->>'areaId' AND NOT (current_data->'excludedRows') @> jsonb_build_array(n);
  SELECT count(*),sum((r->>'maximumSeats')::integer-CASE WHEN (r->>'rowNumber')::integer=ANY(blocked) THEN cardinality(string_to_array(r->>'grouping','-')) ELSE 0 END) INTO available,usable FROM jsonb_array_elements(physical) r WHERE r->>'maximumSeats' IS NOT NULL;
  IF expected>0 AND available=expected AND usable<>(item->>'totalSeats')::integer THEN RAISE EXCEPTION 'D9 usable seats do not match D8 and blocked rows' USING errcode='23514'; END IF;
  INSERT INTO "Basic_Carrier_Record"."Aircraft_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code","Configuration_Code_Description","Cabin_Area_ID","Seat_Class_Code_1","Seat_Class_Code_2","Seat_Class_Code_3","Seat_Class_Code_4","Total_Seats_Cabin_Area_ID","Cabin_Area_BA_Centroid","Cabin_Area_BA_Start","Cabin_Area_BA_End","Cabin_Area_Index_Per_Weight_Unit","Blocked_Centre_Rows")
  VALUES(p_iata,tc,st,code,description,btrim(item->>'areaId'),(item->'classSeats'->>0)::integer,(item->'classSeats'->>1)::integer,(item->'classSeats'->>2)::integer,(item->'classSeats'->>3)::integer,(item->>'totalSeats')::integer,(item->>'centroid')::double precision,(item->>'from')::double precision,(item->>'to')::double precision,(item->>'index')::double precision,blocked);
 END LOOP;
 RETURN "Basic_Carrier_Record".get_aircraft_d9(p_iata,tc,st);
END;
$function$
;
commit;