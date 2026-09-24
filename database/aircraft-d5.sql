begin;

alter table "Basic_Carrier_Record"."Aircraft_Cabin_Areas"
 add constraint "Aircraft_Cabin_Areas_Row_Range_check" check ("Cabin_Area_Start_Row">0 and "Cabin_Area_End_Row">= "Cabin_Area_Start_Row"),
 add constraint "Aircraft_Cabin_Areas_BA_Range_check" check ("Cabin_Area_BA_Start" is null or "Cabin_Area_BA_Centroid" between "Cabin_Area_BA_Start" and "Cabin_Area_BA_End");
alter table "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations"
 add constraint "Aircraft_Flight_Deck_Locations_Seats_check" check ("Location_No_Of_Seats" is null or "Location_No_Of_Seats">0);
alter table "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations"
 add constraint "Aircraft_Cabin_Crew_Locations_Seats_check" check ("Location_No_Of_Seats">0);

create or replace function "Basic_Carrier_Record".get_aircraft_d5(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');areas jsonb;flight jsonb;cabin jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Cabin_Area_ID"),'deck',btrim("Cabin_Area_Deck"),'startRow',"Cabin_Area_Start_Row",'endRow',"Cabin_Area_End_Row",'centroid',"Cabin_Area_BA_Centroid",'startArm',"Cabin_Area_BA_Start",'endArm',"Cabin_Area_BA_End",'index',"Cabin_Area_Index_Per_Weight_Unit") order by btrim("Cabin_Area_ID")),'[]') into areas from "Basic_Carrier_Record"."Aircraft_Cabin_Areas" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Location_Short_Form_ID"),'description',btrim("Location_Description"),'seats',"Location_No_Of_Seats",'centroid',"Location_BA_Centroid",'index',"Location_Index_Per_Weight_Unit") order by btrim("Location_Short_Form_ID")),'[]') into flight from "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Location_Short_Form_ID"),'description',btrim("Location_Description"),'seats',"Location_No_Of_Seats",'centroid',"Location_BA_Centroid",'index',"Location_Index_Per_Weight_Unit") order by btrim("Location_Short_Form_ID")),'[]') into cabin from "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((areas||flight||cabin)::text),'typeCode',tc,'subtype',st,'cabinAreas',areas,'flightDeckLocations',flight,'cabinCrewLocations',cabin);
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_d5(text,text,text) from public,anon;grant execute on function "Basic_Carrier_Record".get_aircraft_d5(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_d5(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if "Basic_Carrier_Record".get_aircraft_d5(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023';end if;
 if p_section='cabinAreas' then
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
revoke all on function "Basic_Carrier_Record".save_aircraft_d5(text,text,text,text,text,jsonb) from public,anon;grant execute on function "Basic_Carrier_Record".save_aircraft_d5(text,text,text,text,text,jsonb) to authenticated;
commit;
