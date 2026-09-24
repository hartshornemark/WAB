begin;
alter table "Basic_Carrier_Record"."Aircraft_Holds" add column if not exists "Floor_Loading_Limit" double precision;
alter table "Basic_Carrier_Record"."Aircraft_Holds" drop constraint if exists "Aircraft_Holds_Floor_Loading_Limit_check";
alter table "Basic_Carrier_Record"."Aircraft_Holds" add constraint "Aircraft_Holds_Floor_Loading_Limit_check" check ("Floor_Loading_Limit" is null or ("Floor_Loading_Limit" > 0 and "Floor_Loading_Limit" <= 1000000000));
create or replace function "Basic_Carrier_Record".get_aircraft_d11(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');rows jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('holdId',btrim(h."Hold_Name_ID"),'holdType',btrim(h."Hold_Type"),'deckName',coalesce(d."Deck_Display_Name",h."Hold_Deck_Location"),'floorLoadingLimit',h."Floor_Loading_Limit") order by btrim(h."Hold_Type"),btrim(h."Hold_Name_ID")),'[]'::jsonb) into rows
 from "Basic_Carrier_Record"."Aircraft_Holds" h left join "Basic_Carrier_Record"."MASTER_Deck_Types" d on d."Deck_Code"=h."Hold_Deck_Location"
 where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(rows::text),'typeCode',tc,'subtype',st,'floorLimits',rows);
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_d11(text,text,text) from public,anon;grant execute on function "Basic_Carrier_Record".get_aircraft_d11(text,text,text) to authenticated;
create or replace function "Basic_Carrier_Record".save_aircraft_d11(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;item jsonb;hold_id text;limit_value double precision;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_d11(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<>(select count(*) from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Every hold requires a floor loading limit' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_rows) loop hold_id:=upper(btrim(item->>'holdId'));limit_value:=(item->>'floorLoadingLimit')::double precision;if limit_value<=0 then raise exception 'Invalid floor loading limit' using errcode='23514';end if;update "Basic_Carrier_Record"."Aircraft_Holds" set "Floor_Loading_Limit"=limit_value where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id;if not found then raise exception 'Unknown hold' using errcode='23503';end if;end loop;
 return "Basic_Carrier_Record".get_aircraft_d11(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_d11(text,text,text,text,jsonb) from public,anon;grant execute on function "Basic_Carrier_Record".save_aircraft_d11(text,text,text,text,jsonb) to authenticated;
commit;
