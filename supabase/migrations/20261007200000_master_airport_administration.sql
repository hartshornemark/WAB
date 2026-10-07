begin;

create function private.is_solution_administrator()
returns boolean language sql stable security definer set search_path='' as $$
  select (select auth.uid()) is not null and exists(
    select 1
    from application_security.user_global_roles ugr
    join application_security.roles r on r.role_id=ugr.role_id
    where ugr.user_id=(select auth.uid())
      and ugr.active
      and r.active
      and r.role_code='SOLUTION_ADMINISTRATOR'
      and ugr.valid_from<=now()
      and (ugr.valid_until is null or ugr.valid_until>now())
  );
$$;
revoke all on function private.is_solution_administrator() from public,anon,authenticated;

create function "Basic_Carrier_Record".get_master_airport_configuration()
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

create function "Basic_Carrier_Record".save_master_airport(p_original_iata text,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  original_iata text:=nullif(upper(btrim(p_original_iata)),'');
  iata text:=upper(btrim(p_values->>'iata'));
  icao text:=nullif(upper(btrim(p_values->>'icao')),'');
  airport_name text:=btrim(p_values->>'name');
  city text:=nullif(btrim(p_values->>'city'),'');
  country text:=nullif(upper(btrim(p_values->>'countryCode')),'');
  time_zone text:=btrim(p_values->>'timeZone');
  is_active boolean:=coalesce((p_values->>'active')::boolean,true);
  saved "Basic_Carrier_Record"."MASTER_Airports"%rowtype;
begin
  if not private.is_solution_administrator() then
    raise exception 'Solution Administrator access required' using errcode='42501';
  end if;
  if iata !~ '^[A-Z]{3}$' then raise exception 'Enter a three-letter IATA airport code' using errcode='22023',detail='iata';end if;
  if icao is not null and icao !~ '^[A-Z0-9]{4}$' then raise exception 'Enter a four-character ICAO airport code' using errcode='22023',detail='icao';end if;
  if char_length(airport_name) not between 1 and 160 then raise exception 'Enter an airport name of up to 160 characters' using errcode='22023',detail='name';end if;
  if city is not null and char_length(city)>120 then raise exception 'Keep the city name within 120 characters' using errcode='22023',detail='city';end if;
  if country is not null and country !~ '^[A-Z]{2}$' then raise exception 'Enter a two-letter country code' using errcode='22023',detail='countryCode';end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=time_zone) then raise exception 'Select a valid IANA time zone' using errcode='22023',detail='timeZone';end if;

  if original_iata is null then
    insert into "Basic_Carrier_Record"."MASTER_Airports"(
      "Airport_IATA","Airport_ICAO","Airport_Name","City_Name","Country_Code","IANA_Time_Zone","Active","Updated_At"
    ) values(iata,icao,airport_name,city,country,time_zone,is_active,now())
    returning * into saved;
  else
    if original_iata<>iata then raise exception 'The IATA identity cannot be changed; deactivate it and add a new airport' using errcode='22023',detail='iata';end if;
    update "Basic_Carrier_Record"."MASTER_Airports" set
      "Airport_ICAO"=icao,"Airport_Name"=airport_name,"City_Name"=city,"Country_Code"=country,
      "IANA_Time_Zone"=time_zone,"Active"=is_active,"Updated_At"=now()
    where "Airport_IATA"=original_iata returning * into saved;
    if not found then raise exception 'Airport not found' using errcode='P0002';end if;
  end if;

  return jsonb_build_object(
    'iata',btrim(saved."Airport_IATA"),'icao',nullif(btrim(saved."Airport_ICAO"),''),'name',btrim(saved."Airport_Name"),
    'city',nullif(btrim(saved."City_Name"),''),'countryCode',nullif(btrim(saved."Country_Code"),''),
    'timeZone',saved."IANA_Time_Zone",'active',saved."Active",'updatedAt',saved."Updated_At"
  );
exception when unique_violation then
  raise exception 'That IATA or ICAO airport code already exists' using errcode='23505',detail=case when exists(select 1 from "Basic_Carrier_Record"."MASTER_Airports" where "Airport_IATA"=iata) then 'iata' else 'icao' end;
end $$;

revoke all on function "Basic_Carrier_Record".get_master_airport_configuration() from public,anon;
revoke all on function "Basic_Carrier_Record".save_master_airport(text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_master_airport_configuration() to authenticated;
grant execute on function "Basic_Carrier_Record".save_master_airport(text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
