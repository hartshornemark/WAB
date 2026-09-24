begin;

alter table "Basic_Carrier_Record"."Aircraft_Potable_Water_Codes"
  drop constraint if exists "Aircraft_Potable_Water_Codes_PW_Location_FK";
alter table "Basic_Carrier_Record"."Aircraft_Potable_Water_Codes"
  add constraint "Aircraft_Potable_Water_Codes_PW_Location_FK"
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","PW_Tank_Short_Form","Aircraft_Series_Subtype")
  references "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations"("Carrier_IATA","Aircraft_Type_IATA","PW_Tank_Short_Form","Aircraft_Series_Subtype")
  on update cascade;

alter table "Basic_Carrier_Record"."Carrier_Potable_Water_Codes"
  drop constraint if exists "Carrier_Potable_Water_Codes_PW_Tank_Name_FK";
alter table "Basic_Carrier_Record"."Carrier_Potable_Water_Codes"
  add constraint "Carrier_Potable_Water_Codes_PW_Tank_Name_FK"
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","PW_Tank_Name","Aircraft_Series_Subtype")
  references "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations"("Carrier_IATA","Aircraft_Type_IATA","PW_Tank_Name","Aircraft_Series_Subtype")
  on update cascade;

create or replace function "Basic_Carrier_Record".save_aircraft_d6(p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if "Basic_Carrier_Record".get_aircraft_d6(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023';end if;
 if p_section='waterLocations' then
  for item in select value from jsonb_array_elements(p_rows) loop
   insert into "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","PW_Tank_Name","PW_Tank_Short_Form","PW_Tank_Max_Weight","PW_Tank_BA_Centroid","PW_Tnk_Index_Per_Weight_Unit")
   values(p_iata,tc,st,btrim(item->>'name'),upper(btrim(item->>'id')),(item->>'maxWeight')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision)
   on conflict ("Carrier_IATA","Aircraft_Type_IATA","PW_Tank_Short_Form","Aircraft_Series_Subtype") do update set
    "PW_Tank_Name"=excluded."PW_Tank_Name",
    "PW_Tank_Max_Weight"=excluded."PW_Tank_Max_Weight",
    "PW_Tank_BA_Centroid"=excluded."PW_Tank_BA_Centroid",
    "PW_Tnk_Index_Per_Weight_Unit"=excluded."PW_Tnk_Index_Per_Weight_Unit";
  end loop;
  delete from "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations" w
   where w."Carrier_IATA"=p_iata and w."Aircraft_Type_IATA"=tc and w."Aircraft_Series_Subtype"=st
     and not exists(select 1 from jsonb_array_elements(p_rows) r where upper(btrim(r->>'id'))=btrim(w."PW_Tank_Short_Form"));
 elsif p_section='galleyLocations' then
  delete from "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  for item in select value from jsonb_array_elements(p_rows) loop insert into "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Location_Description","Location_Short_Form_ID","Location_Max_Weight","Location_BA_Centroid","Location_Index_Per_Weight_Unit") values(p_iata,tc,st,btrim(item->>'description'),upper(btrim(item->>'id')),(item->>'maxWeight')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision);end loop;
 else raise exception 'Unknown section' using errcode='22023';end if;
 return "Basic_Carrier_Record".get_aircraft_d6(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".save_aircraft_d6(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d6(text,text,text,text,text,jsonb) to authenticated;

commit;
