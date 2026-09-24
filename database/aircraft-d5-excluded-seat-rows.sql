begin;

create table if not exists "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Seat_Row_Number" integer not null,
  constraint "Aircraft_Excluded_Seat_Rows_pkey"
    primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Seat_Row_Number"),
  constraint "Aircraft_Excluded_Seat_Rows_number_check"
    check ("Seat_Row_Number" between 1 and 99),
  constraint "Aircraft_Excluded_Seat_Rows_aircraft_fkey"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data"
      ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update cascade on delete cascade
);

alter table "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" enable row level security;
revoke all on table "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".get_aircraft_d5(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');excluded jsonb;areas jsonb;flight jsonb;cabin jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg("Seat_Row_Number" order by "Seat_Row_Number"),'[]') into excluded from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'deck',btrim("Cabin_Area_Deck"),'startRow',"Cabin_Area_Start_Row",'endRow',"Cabin_Area_End_Row",'centroid',"Cabin_Area_BA_Centroid",'startArm',"Cabin_Area_BA_Start",'endArm',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by btrim("Cabin_Area_ID")),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Location_Short_Form_ID"),'description',btrim("Location_Description"),'seats',"Location_No_Of_Seats",'centroid',"Location_BA_Centroid",'index',"Location_Index_Per_Weight_Unit") order by btrim("Location_Short_Form_ID")),'[]') into flight from "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Location_Short_Form_ID"),'description',btrim("Location_Description"),'seats',"Location_No_Of_Seats",'centroid',"Location_BA_Centroid",'index',"Location_Index_Per_Weight_Unit") order by btrim("Location_Short_Form_ID")),'[]') into cabin from "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((excluded||areas||flight||cabin)::text),'typeCode',tc,'subtype',st,'excludedRows',excluded,'cabinAreas',areas,'flightDeckLocations',flight,'cabinCrewLocations',cabin);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_d5(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;row_number integer;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
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
  delete from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  for item in select value from jsonb_array_elements(p_rows) loop insert into "Basic_Carrier_Record"."Aircraft_Cabin_Areas"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Cabin_Area_ID","Cabin_Area_Deck","Cabin_Area_Start_Row","Cabin_Area_End_Row","Cabin_Area_BA_Centroid","Cabin_Area_BA_Start","Cabin_Area_BA_End","Cabin_Area_Index_Per_Weight_Unit") values(p_iata,tc,st,upper(btrim(item->>'id')),upper(btrim(item->>'deck')),(item->>'startRow')::integer,(item->>'endRow')::integer,(item->>'centroid')::double precision,(item->>'startArm')::double precision,(item->>'endArm')::double precision,(item->>'index')::double precision);end loop;
 elsif p_section in('flightDeckLocations','cabinCrewLocations') then
  if p_section='flightDeckLocations' then delete from "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;else delete from "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;end if;
  for item in select value from jsonb_array_elements(p_rows) loop
   if p_section='flightDeckLocations' then insert into "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Location_Short_Form_ID","Location_Description","Location_No_Of_Seats","Location_BA_Centroid","Location_Index_Per_Weight_Unit") values(p_iata,tc,st,upper(btrim(item->>'id')),btrim(item->>'description'),(item->>'seats')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision);
   else insert into "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Location_Short_Form_ID","Location_Description","Location_No_Of_Seats","Location_BA_Centroid","Location_Index_Per_Weight_Unit") values(p_iata,tc,st,upper(btrim(item->>'id')),btrim(item->>'description'),(item->>'seats')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision);end if;
  end loop;
 else raise exception 'Unknown section' using errcode='22023';end if;
 return "Basic_Carrier_Record".get_aircraft_d5(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".get_aircraft_d8(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');excluded jsonb;areas jsonb;rows jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg("Seat_Row_Number" order by "Seat_Row_Number"),'[]') into excluded from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'rowFrom',"Cabin_Area_Start_Row",'rowTo',"Cabin_Area_End_Row") order by "Cabin_Area_Start_Row"),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim(r."Seat_Row_Cabin_Area"),'rowNumber',btrim(r."Seat_Row_Number")::integer,'maximumSeats',r."Seat_Row_Seats",'maximumWeight',r."Seat_Row_Max_Weight",'centroid',r."Seat_Row_BA",'index',r."Seat_Row_Index_Per_Weight_Unit") order by btrim(r."Seat_Row_Number")::integer),'[]') into rows from "Basic_Carrier_Record"."Aircraft_Seat_Rows" r where r."Carrier_IATA"=p_iata and r."Aircraft_Type_IATA"=tc and r."Aircraft_Series_Subtype"=st and not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" e where e."Carrier_IATA"=r."Carrier_IATA" and e."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and e."Aircraft_Series_Subtype"=r."Aircraft_Series_Subtype" and e."Seat_Row_Number"=btrim(r."Seat_Row_Number")::integer);
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((excluded||areas||rows)::text),'typeCode',tc,'subtype',st,'excludedRows',excluded,'cabinAreas',areas,'rows',rows);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_d8(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;area_row record;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if "Basic_Carrier_Record".get_aircraft_d8(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one complete row required' using errcode='22023';end if;
 delete from "Basic_Carrier_Record"."Aircraft_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 for item in select value from jsonb_array_elements(p_rows) loop
  if exists(select 1 from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Seat_Row_Number"=(item->>'rowNumber')::integer) then raise exception 'Excluded seat row' using errcode='23514';end if;
  select "Cabin_Area_Start_Row" as row_from,"Cabin_Area_End_Row" as row_to into area_row from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Cabin_Area_ID")=btrim(item->>'areaId');
  if not found or (item->>'rowNumber')::integer not between area_row.row_from and area_row.row_to then raise exception 'Seat row outside cabin area' using errcode='23514';end if;
  insert into "Basic_Carrier_Record"."Aircraft_Seat_Rows"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Seat_Row_Number","Seat_Row_Cabin_Area","Seat_Row_Seats","Seat_Row_Max_Weight","Seat_Row_BA","Seat_Row_Index_Per_Weight_Unit") values(p_iata,tc,st,(item->>'rowNumber')::integer::text,btrim(item->>'areaId'),(item->>'maximumSeats')::integer,case when item->'maximumWeight'='null'::jsonb then null else (item->>'maximumWeight')::integer end,(item->>'centroid')::double precision,(item->>'index')::double precision);
 end loop;
 return "Basic_Carrier_Record".get_aircraft_d8(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".get_aircraft_d9(p_iata text,p_type_code text,p_subtype text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');excluded jsonb;areas jsonb;classes jsonb;configs jsonb:='[]';cfg record;rows jsonb;
begin if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select coalesce(jsonb_agg("Seat_Row_Number" order by "Seat_Row_Number"),'[]') into excluded from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'rowFrom',"Cabin_Area_Start_Row",'rowTo',"Cabin_Area_End_Row",'centroid',"Cabin_Area_BA_Centroid",'from',"Cabin_Area_BA_Start",'to',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by "Cabin_Area_Start_Row"),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_build_array(jsonb_build_object('slot',1,'code',btrim("Carrier_Class_1_Code"),'name',btrim("Carrier_Class_1_Name")),jsonb_build_object('slot',2,'code',btrim("Carrier_Class_2_Code"),'name',btrim("Carrier_Class_2_Name")),jsonb_build_object('slot',3,'code',btrim("Carrier_Class_3_Code"),'name',btrim("Carrier_Class_3_Name")),jsonb_build_object('slot',4,'code',btrim("Carrier_Class_4_Code"),'name',btrim("Carrier_Class_4_Name"))),'[]') into classes from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"=p_iata;
 for cfg in select btrim("Configuration_Code") code,min(btrim("Configuration_Code_Description")) description from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st group by btrim("Configuration_Code") order by 1 loop
  select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim("Cabin_Area_ID"),'classSeats',jsonb_build_array("Seat_Class_Code_1",coalesce("Seat_Class_Code_2",0),coalesce("Seat_Class_Code_3",0),coalesce("Seat_Class_Code_4",0)),'totalSeats',"Total_Seats_Cabin_Area_ID",'centroid',"Cabin_Area_BA_Centroid",'from',"Cabin_Area_BA_Start",'to',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by btrim("Cabin_Area_ID")),'[]') into rows from "Basic_Carrier_Record"."Aircraft_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Configuration_Code")=cfg.code;
  configs:=configs||jsonb_build_array(jsonb_build_object('code',cfg.code,'description',cfg.description,'rows',rows));end loop;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((excluded||areas||classes||configs)::text),'typeCode',tc,'subtype',st,'excludedRows',excluded,'cabinAreas',areas,'classes',classes,'configurations',configs);end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_d5(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d5(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_d5(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d5(text,text,text,text,text,jsonb) to authenticated;
revoke all on function "Basic_Carrier_Record".get_aircraft_d8(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d8(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_d8(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d8(text,text,text,text,jsonb) to authenticated;
revoke all on function "Basic_Carrier_Record".get_aircraft_d9(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d9(text,text,text) to authenticated;

commit;
