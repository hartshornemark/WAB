begin;

create or replace function "Basic_Carrier_Record".get_master_airport_configuration()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_solution_administrator() then
    raise exception 'Solution Administrator access required' using errcode='42501';
  end if;
  return jsonb_build_object(
    'airports',coalesce((
      select jsonb_agg(jsonb_build_object(
        'iata',btrim(a."Airport_IATA"),
        'icao',nullif(btrim(a."Airport_ICAO"),''),
        'name',btrim(a."Airport_Name"),
        'city',nullif(btrim(a."City_Name"),''),
        'countryCode',nullif(btrim(a."Country_Code"),''),
        'timeZone',a."IANA_Time_Zone",
        'active',a."Active",
        'updatedAt',a."Updated_At"
      ) order by a."Airport_IATA")
      from "Basic_Carrier_Record"."MASTER_Airports" a
    ),'[]'::jsonb),
    'timeZones',coalesce((
      select jsonb_agg(name order by name)
      from pg_catalog.pg_timezone_names
      where name='UTC' or (name ~ '^[A-Za-z]+(?:[_+-][A-Za-z0-9]+)*/' and name !~ '^(posix|right)/')
    ),'[]'::jsonb)
  );
end $$;

notify pgrst,'reload schema';
commit;
