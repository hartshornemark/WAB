begin;

alter table "Basic_Carrier_Record"."Aircraft_Seat_Rows"
  add constraint "Aircraft_Seat_Rows_Row_Number_check" check (btrim("Seat_Row_Number") ~ '^[1-9][0-9]?$'),
  add constraint "Aircraft_Seat_Rows_Seats_check" check ("Seat_Row_Seats">0),
  add constraint "Aircraft_Seat_Rows_Max_Weight_check" check ("Seat_Row_Max_Weight" is null or "Seat_Row_Max_Weight">0),
  add constraint "Aircraft_Seat_Rows_BA_check" check (abs("Seat_Row_BA")<=1000000000),
  add constraint "Aircraft_Seat_Rows_Index_check" check (abs("Seat_Row_Index_Per_Weight_Unit")<=1000000000),
  add constraint "Aircraft_Seat_Rows_Cabin_Area_fkey" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Seat_Row_Cabin_Area","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Aircraft_Cabin_Areas"("Carrier_IATA","Aircraft_Type_IATA","Cabin_Area_ID","Aircraft_Series_Subtype");

create or replace function "Basic_Carrier_Record".get_aircraft_d8(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');areas jsonb;rows jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'rowFrom',"Cabin_Area_Start_Row",'rowTo',"Cabin_Area_End_Row") order by "Cabin_Area_Start_Row"),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('areaId',btrim("Seat_Row_Cabin_Area"),'rowNumber',btrim("Seat_Row_Number")::integer,'maximumSeats',"Seat_Row_Seats",'maximumWeight',"Seat_Row_Max_Weight",'centroid',"Seat_Row_BA",'index',"Seat_Row_Index_Per_Weight_Unit") order by btrim("Seat_Row_Number")::integer),'[]') into rows from "Basic_Carrier_Record"."Aircraft_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((areas||rows)::text),'typeCode',tc,'subtype',st,'cabinAreas',areas,'rows',rows);
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_d8(text,text,text) from public,anon;grant execute on function "Basic_Carrier_Record".get_aircraft_d8(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_d8(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;area_row record;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if "Basic_Carrier_Record".get_aircraft_d8(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one complete row required' using errcode='22023';end if;
 delete from "Basic_Carrier_Record"."Aircraft_Seat_Rows" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 for item in select value from jsonb_array_elements(p_rows) loop
  select "Cabin_Area_Start_Row" as row_from,"Cabin_Area_End_Row" as row_to into area_row from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Cabin_Area_ID")=btrim(item->>'areaId');
  if not found or (item->>'rowNumber')::integer not between area_row.row_from and area_row.row_to then raise exception 'Seat row outside cabin area' using errcode='23514';end if;
  insert into "Basic_Carrier_Record"."Aircraft_Seat_Rows"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Seat_Row_Number","Seat_Row_Cabin_Area","Seat_Row_Seats","Seat_Row_Max_Weight","Seat_Row_BA","Seat_Row_Index_Per_Weight_Unit") values(p_iata,tc,st,(item->>'rowNumber')::integer::text,btrim(item->>'areaId'),(item->>'maximumSeats')::integer,case when item->'maximumWeight'='null'::jsonb then null else (item->>'maximumWeight')::integer end,(item->>'centroid')::double precision,(item->>'index')::double precision);
 end loop;
 return "Basic_Carrier_Record".get_aircraft_d8(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_d8(text,text,text,text,jsonb) from public,anon;grant execute on function "Basic_Carrier_Record".save_aircraft_d8(text,text,text,text,jsonb) to authenticated;
commit;
