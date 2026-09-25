-- Optional cabin-area defaults and row overrides. Existing rows remain unchanged.
begin;
alter table "Basic_Carrier_Record"."Aircraft_Cabin_Areas"
 add column "Seat_Grouping_Default" text,
 add constraint "Cabin_Area_Seat_Grouping_check" check ("Seat_Grouping_Default" ~ '^[1-9](-[1-9]){0,3}$');
alter table "Basic_Carrier_Record"."Aircraft_Seat_Rows"
 add column "Seat_Grouping_Override" text,
 add constraint "Seat_Row_Grouping_check" check ("Seat_Grouping_Override" ~ '^[1-9](-[1-9]){0,3}$');
comment on column "Basic_Carrier_Record"."Aircraft_Cabin_Areas"."Seat_Grouping_Default" is 'Optional seat groups left to right facing the nose; hyphens represent aisles.';
comment on column "Basic_Carrier_Record"."Aircraft_Seat_Rows"."Seat_Grouping_Override" is 'Null inherits the cabin-area default; otherwise the row-specific seat grouping.';
create or replace function private.d8_grouping_seats(p_grouping text) returns integer
language plpgsql immutable strict security invoker set search_path='' as $$
begin
 if p_grouping !~ '^[1-9](-[1-9]){0,3}$' then raise exception 'Invalid seat grouping' using errcode='23514';end if;
 return (select sum(value::integer)::integer from unnest(string_to_array(p_grouping,'-')) value);
end $$;
revoke all on function private.d8_grouping_seats(text) from public,anon,authenticated;
create or replace function "Basic_Carrier_Record".get_aircraft_d8(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');excluded jsonb;areas jsonb;rows jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg("Seat_Row_Number" order by "Seat_Row_Number"),'[]') into excluded from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'rowFrom',"Cabin_Area_Start_Row",'rowTo',"Cabin_Area_End_Row",'seatGrouping',"Seat_Grouping_Default") order by "Cabin_Area_Start_Row"),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim(r."Seat_Row_Cabin_Area"),'rowNumber',btrim(r."Seat_Row_Number")::integer,'maximumSeats',r."Seat_Row_Seats",'maximumWeight',r."Seat_Row_Max_Weight",'centroid',r."Seat_Row_BA",'index',r."Seat_Row_Index_Per_Weight_Unit",'seatGroupingOverride',r."Seat_Grouping_Override") order by btrim(r."Seat_Row_Number")::integer),'[]') into rows from "Basic_Carrier_Record"."Aircraft_Seat_Rows" r where r."Carrier_IATA"=p_iata and r."Aircraft_Type_IATA"=tc and r."Aircraft_Series_Subtype"=st and not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Excluded_Seat_Rows" e where e."Carrier_IATA"=r."Carrier_IATA" and e."Aircraft_Type_IATA"=r."Aircraft_Type_IATA" and e."Aircraft_Series_Subtype"=r."Aircraft_Series_Subtype" and e."Seat_Row_Number"=btrim(r."Seat_Row_Number")::integer);
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((excluded||areas||rows)::text),'typeCode',tc,'subtype',st,'excludedRows',excluded,'cabinAreas',areas,'rows',rows);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_d8(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
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
  select "Cabin_Area_Start_Row" as row_from,"Cabin_Area_End_Row" as row_to,"Seat_Grouping_Default" as seat_grouping into area_row from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Cabin_Area_ID")=btrim(item->>'areaId');
  if not found or (item->>'rowNumber')::integer not between area_row.row_from and area_row.row_to then raise exception 'Seat row outside cabin area' using errcode='23514';end if;
  v_grouping:=case when legacy then old_overrides->>(item->>'rowNumber') else nullif(btrim(item->>'seatGroupingOverride'),'') end;
  if private.d8_grouping_seats(coalesce(v_grouping,area_row.seat_grouping)) is distinct from null
     and private.d8_grouping_seats(coalesce(v_grouping,area_row.seat_grouping))<>(item->>'maximumSeats')::integer then
   raise exception 'Seat grouping does not match row seats' using errcode='23514';
  end if;
  insert into "Basic_Carrier_Record"."Aircraft_Seat_Rows"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Seat_Row_Number","Seat_Row_Cabin_Area","Seat_Row_Seats","Seat_Row_Max_Weight","Seat_Row_BA","Seat_Row_Index_Per_Weight_Unit","Seat_Grouping_Override") values(p_iata,tc,st,(item->>'rowNumber')::integer::text,btrim(item->>'areaId'),(item->>'maximumSeats')::integer,case when item->'maximumWeight'='null'::jsonb then null else (item->>'maximumWeight')::integer end,(item->>'centroid')::double precision,(item->>'index')::double precision,v_grouping);
 end loop;
 return "Basic_Carrier_Record".get_aircraft_d8(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_d5(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;row_number integer;groupings jsonb;
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
  select coalesce(jsonb_object_agg(btrim("Cabin_Area_ID"),"Seat_Grouping_Default"),'{}') into groupings from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  delete from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st
   and btrim("Cabin_Area_ID") not in (select upper(btrim(value->>'id')) from jsonb_array_elements(p_rows));
  for item in select value from jsonb_array_elements(p_rows) loop insert into "Basic_Carrier_Record"."Aircraft_Cabin_Areas"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Cabin_Area_ID","Cabin_Area_Deck","Cabin_Area_Start_Row","Cabin_Area_End_Row","Cabin_Area_BA_Centroid","Cabin_Area_BA_Start","Cabin_Area_BA_End","Cabin_Area_Index_Per_Weight_Unit","Seat_Grouping_Default") values(p_iata,tc,st,upper(btrim(item->>'id')),upper(btrim(item->>'deck')),(item->>'startRow')::integer,(item->>'endRow')::integer,(item->>'centroid')::double precision,(item->>'startArm')::double precision,(item->>'endArm')::double precision,(item->>'index')::double precision,groupings->>upper(btrim(item->>'id')))
  on conflict ("Carrier_IATA","Aircraft_Type_IATA","Cabin_Area_ID","Aircraft_Series_Subtype") do update set
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
 return "Basic_Carrier_Record".get_aircraft_d5(p_iata,tc,st);
end $$;
-- Existing carrier/global aircraft permissions continue to govern these RPCs.
revoke all on function "Basic_Carrier_Record".get_aircraft_d8(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d8(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_d8(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d8(text,text,text,text,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
