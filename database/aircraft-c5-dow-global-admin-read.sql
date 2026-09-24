begin;

create or replace function private.aircraft_effective_dow(p_iata text,p_type_code text,p_subtype text)
returns integer language plpgsql stable security definer set search_path='' as $$
declare fleet_dow integer;standard_weight integer;
begin
  if (select auth.uid()) is null or not (
    private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or
    private.has_global_permission('AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')
  ) then raise exception 'Not authorised' using errcode='42501';end if;
  select min("Dry_Operating_Weight") into fleet_dow from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=upper(btrim(p_type_code)) and "Aircraft_Series_Subtype"=upper(btrim(p_subtype)) and "Dry_Operating_Weight">0;
  if fleet_dow is not null then return fleet_dow;end if;
  select "Standard_Fleet_Weight" into standard_weight from "Basic_Carrier_Record"."Basic_Aircraft_Data"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=upper(btrim(p_type_code)) and "Aircraft_Series_Subtype"=upper(btrim(p_subtype));
  return coalesce(case when standard_weight>0 then standard_weight end,0);
end $$;
revoke all on function private.aircraft_effective_dow(text,text,text) from public,anon;
grant execute on function private.aircraft_effective_dow(text,text,text) to authenticated;

create or replace function private.aircraft_effective_dow_source(p_iata text,p_type_code text,p_subtype text)
returns text language plpgsql stable security definer set search_path='' as $$
begin
  if (select auth.uid()) is null or not (
    private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or
    private.has_global_permission('AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')
  ) then raise exception 'Not authorised' using errcode='42501';end if;
  if exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=upper(btrim(p_type_code)) and "Aircraft_Series_Subtype"=upper(btrim(p_subtype)) and "Dry_Operating_Weight">0) then return 'fleet';end if;
  if exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=upper(btrim(p_type_code)) and "Aircraft_Series_Subtype"=upper(btrim(p_subtype)) and "Standard_Fleet_Weight">0) then return 'standard';end if;
  return 'unavailable';
end $$;
revoke all on function private.aircraft_effective_dow_source(text,text,text) from public,anon;
grant execute on function private.aircraft_effective_dow_source(text,text,text) to authenticated;

create or replace function "Basic_Carrier_Record".get_aircraft_c5_effective_dow(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
  return jsonb_build_object('value',private.aircraft_effective_dow(p_iata,p_type_code,p_subtype),'source',private.aircraft_effective_dow_source(p_iata,p_type_code,p_subtype));
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_c5_effective_dow(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c5_effective_dow(text,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
