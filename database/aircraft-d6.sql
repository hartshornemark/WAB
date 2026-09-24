begin;

alter table "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations"
  add constraint "Aircraft_Potable_Water_Locations_ID_check" check (btrim("PW_Tank_Short_Form") ~ '^[A-Z0-9]{1,3}$'),
  add constraint "Aircraft_Potable_Water_Locations_Max_Weight_check" check ("PW_Tank_Max_Weight">0),
  add constraint "Aircraft_Potable_Water_Locations_Index_check" check ("PW_Tnk_Index_Per_Weight_Unit" is not null and abs("PW_Tnk_Index_Per_Weight_Unit")<=1000000000);
alter table "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations"
  add constraint "Aircraft_Galley_and_Other_Locations_ID_check" check (btrim("Location_Short_Form_ID") ~ '^[A-Z0-9]{1,3}$'),
  add constraint "Aircraft_Galley_and_Other_Locations_Max_Weight_check" check ("Location_Max_Weight">0),
  add constraint "Aircraft_Galley_and_Other_Locations_Index_check" check ("Location_Index_Per_Weight_Unit" is not null and abs("Location_Index_Per_Weight_Unit")<=1000000000);

create or replace function "Basic_Carrier_Record".get_aircraft_d6(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');water jsonb;galley jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("PW_Tank_Short_Form"),'name',btrim("PW_Tank_Name"),'maxWeight',"PW_Tank_Max_Weight",'centroid',"PW_Tank_BA_Centroid",'index',"PW_Tnk_Index_Per_Weight_Unit") order by btrim("PW_Tank_Short_Form")),'[]') into water from "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim("Location_Short_Form_ID"),'description',btrim("Location_Description"),'maxWeight',"Location_Max_Weight",'centroid',"Location_BA_Centroid",'index',"Location_Index_Per_Weight_Unit") order by btrim("Location_Short_Form_ID")),'[]') into galley from "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5((water||galley)::text),'typeCode',tc,'subtype',st,'waterLocations',water,'galleyLocations',galley);
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_d6(text,text,text) from public,anon;grant execute on function "Basic_Carrier_Record".get_aircraft_d6(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_d6(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if "Basic_Carrier_Record".get_aircraft_d6(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023';end if;
 if p_section='waterLocations' then
  for item in select value from jsonb_array_elements(p_rows) loop
   insert into "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","PW_Tank_Name","PW_Tank_Short_Form","PW_Tank_Max_Weight","PW_Tank_BA_Centroid","PW_Tnk_Index_Per_Weight_Unit") values(p_iata,tc,st,btrim(item->>'name'),upper(btrim(item->>'id')),(item->>'maxWeight')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision)
   on conflict ("Carrier_IATA","Aircraft_Type_IATA","PW_Tank_Short_Form","Aircraft_Series_Subtype") do update set "PW_Tank_Name"=excluded."PW_Tank_Name","PW_Tank_Max_Weight"=excluded."PW_Tank_Max_Weight","PW_Tank_BA_Centroid"=excluded."PW_Tank_BA_Centroid","PW_Tnk_Index_Per_Weight_Unit"=excluded."PW_Tnk_Index_Per_Weight_Unit";
  end loop;
  delete from "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations" w where w."Carrier_IATA"=p_iata and w."Aircraft_Type_IATA"=tc and w."Aircraft_Series_Subtype"=st and not exists(select 1 from jsonb_array_elements(p_rows) r where upper(btrim(r->>'id'))=btrim(w."PW_Tank_Short_Form"));
 elsif p_section='galleyLocations' then
  delete from "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  for item in select value from jsonb_array_elements(p_rows) loop insert into "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Location_Description","Location_Short_Form_ID","Location_Max_Weight","Location_BA_Centroid","Location_Index_Per_Weight_Unit") values(p_iata,tc,st,btrim(item->>'description'),upper(btrim(item->>'id')),(item->>'maxWeight')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision);end loop;
 else raise exception 'Unknown section' using errcode='22023';end if;
 return "Basic_Carrier_Record".get_aircraft_d6(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_d6(text,text,text,text,text,jsonb) from public,anon;grant execute on function "Basic_Carrier_Record".save_aircraft_d6(text,text,text,text,text,jsonb) to authenticated;
commit;
