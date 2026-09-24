begin;

create or replace function "Basic_Carrier_Record".get_aircraft_d4(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');door_rows jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'holdId',btrim(h."Hold_Name_ID"),
   'holdType',btrim(h."Hold_Type"),
   'deckName',coalesce(d."Deck_Display_Name",h."Hold_Deck_Location"),
   'forwardArm',h."Hold_DOOR_Start",
   'aftArm',h."Hold_DOOR_End",
   'height',h."Hold_DOOR_Height",
   'orientation',nullif(btrim(h."Hold_DOOR_Orientation"),'')
 ) order by
   case when upper(btrim(h."Hold_Type"))='ULD' then 0 else 1 end,
   h."Hold_BA_Centroid" asc nulls last,
   case when btrim(h."Hold_Name_ID") ~ '^[0-9]+$' then btrim(h."Hold_Name_ID")::integer end asc nulls last,
   btrim(h."Hold_Name_ID")
 ),'[]'::jsonb) into door_rows
 from "Basic_Carrier_Record"."Aircraft_Holds" h
 left join "Basic_Carrier_Record"."MASTER_Deck_Types" d on d."Deck_Code"=h."Hold_Deck_Location"
 where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(door_rows::text),'typeCode',tc,'subtype',st,'doors',door_rows);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_d4(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d4(text,text,text) to authenticated;

commit;
