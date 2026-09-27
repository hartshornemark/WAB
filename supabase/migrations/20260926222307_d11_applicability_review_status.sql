begin;

create or replace function "Basic_Carrier_Record".get_aircraft_d11(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
  can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  applicability_reviewed boolean;
  combined_active boolean;
  floor_active boolean;
  asymmetrical_active boolean;
  rows jsonb;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503'; end if;
  select exists(
    select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st
  ) into applicability_reviewed;
  select
    coalesce((select "Combined_Load_Limits_Applicable" from "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),false),
    coalesce((select "Floor_Loading_Limits_Applicable" from "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),false),
    coalesce((select "Asymmetrical_Load_Limits_Applicable" from "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),false)
  into combined_active,floor_active,asymmetrical_active;
  select coalesce(jsonb_agg(jsonb_build_object('holdId',btrim(h."Hold_Name_ID"),'holdType',btrim(h."Hold_Type"),'deckName',coalesce(d."Deck_Display_Name",h."Hold_Deck_Location"),'floorLoadingLimit',h."Floor_Loading_Limit") order by btrim(h."Hold_Type"),btrim(h."Hold_Name_ID")),'[]'::jsonb) into rows
  from "Basic_Carrier_Record"."Aircraft_Holds" h left join "Basic_Carrier_Record"."MASTER_Deck_Types" d on d."Deck_Code"=h."Hold_Deck_Location"
  where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st;
  return jsonb_build_object(
    'canView',can_view,'canEdit',can_edit,
    'revision',md5((jsonb_build_array(applicability_reviewed,combined_active,floor_active,asymmetrical_active)||rows)::text),
    'typeCode',tc,'subtype',st,'applicabilityReviewed',applicability_reviewed,
    'combinedActive',combined_active,'floorActive',floor_active,'asymmetricalActive',asymmetrical_active,
    'floorLimits',rows
  );
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_d11(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d11(text,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
