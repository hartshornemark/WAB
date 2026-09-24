begin;

alter table "Basic_Carrier_Record"."Aircraft_Holds"
  add constraint "Aircraft_Holds_Door_All_Or_None_check" check (
    ("Hold_DOOR_Start" is null and "Hold_DOOR_End" is null and "Hold_DOOR_Height" is null and "Hold_DOOR_Orientation" is null)
    or
    ("Hold_DOOR_Start" is not null and "Hold_DOOR_End" is not null and "Hold_DOOR_Height" is not null and "Hold_DOOR_Orientation" is not null)
  ),
  add constraint "Aircraft_Holds_Door_Arms_check" check ("Hold_DOOR_Start" is null or "Hold_DOOR_Start" <= "Hold_DOOR_End"),
  add constraint "Aircraft_Holds_Door_Height_check" check ("Hold_DOOR_Height" is null or "Hold_DOOR_Height" > 0),
  add constraint "Aircraft_Holds_Door_Orientation_check" check ("Hold_DOOR_Orientation" is null or btrim("Hold_DOOR_Orientation") in ('L','R','C'));

create or replace function "Basic_Carrier_Record".get_aircraft_d4(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');door_rows jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('holdId',btrim(h."Hold_Name_ID"),'holdType',btrim(h."Hold_Type"),'deckName',coalesce(d."Deck_Display_Name",h."Hold_Deck_Location"),'forwardArm',h."Hold_DOOR_Start",'aftArm',h."Hold_DOOR_End",'height',h."Hold_DOOR_Height",'orientation',nullif(btrim(h."Hold_DOOR_Orientation"),'') ) order by btrim(h."Hold_Type"),btrim(h."Hold_Name_ID")),'[]'::jsonb) into door_rows
 from "Basic_Carrier_Record"."Aircraft_Holds" h left join "Basic_Carrier_Record"."MASTER_Deck_Types" d on d."Deck_Code"=h."Hold_Deck_Location"
 where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(door_rows::text),'typeCode',tc,'subtype',st,'doors',door_rows);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_d4(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d4(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".save_aircraft_d4(p_iata text,p_type_code text,p_subtype text,p_revision text,p_doors jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;item jsonb;hold_id text;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st);
 if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if jsonb_typeof(p_doors)<>'array' or jsonb_array_length(p_doors)<>(select count(*) from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Every hold requires one door' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_doors) loop
   hold_id:=upper(btrim(item->>'holdId'));
   update "Basic_Carrier_Record"."Aircraft_Holds" set "Hold_DOOR_Start"=(item->>'forwardArm')::double precision,"Hold_DOOR_End"=(item->>'aftArm')::double precision,"Hold_DOOR_Height"=(item->>'height')::double precision,"Hold_DOOR_Orientation"=upper(btrim(item->>'orientation'))
   where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id;
   if not found then raise exception 'Unknown hold' using errcode='23503';end if;
 end loop;
 return "Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".save_aircraft_d4(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d4(text,text,text,text,jsonb) to authenticated;

commit;
