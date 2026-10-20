begin;

insert into application_security.roles(role_code,role_name,description,active,role_scope)
values(
  'OBSERVER',
  'Observer',
  'Platform-wide read-only access to carrier configuration, aircraft data, schedules, Load Control and master data.',
  true,
  'GLOBAL'
)
on conflict(role_code) do update set
  role_name=excluded.role_name,
  description=excluded.description,
  active=true,
  role_scope='GLOBAL';

insert into application_security.role_permissions(role_id,permission_id)
select r.role_id,p.permission_id
from application_security.roles r
cross join application_security.permissions p
where r.role_code='OBSERVER'
  and p.permission_code in(
    'MASTER_DATA_VIEW',
    'CARRIER_CONFIG_VIEW',
    'FLEET_CONFIG_VIEW',
    'AIRCRAFT_CONFIG_VIEW',
    'OPERATING_CONFIG_VIEW',
    'FLIGHT_SCHEDULE_VIEW',
    'LOAD_CONTROL_VIEW'
  )
on conflict do nothing;

delete from application_security.role_permissions rp
using application_security.roles r,application_security.permissions p
where rp.role_id=r.role_id
  and rp.permission_id=p.permission_id
  and r.role_code='OBSERVER'
  and p.permission_code not in(
    'MASTER_DATA_VIEW',
    'CARRIER_CONFIG_VIEW',
    'FLEET_CONFIG_VIEW',
    'AIRCRAFT_CONFIG_VIEW',
    'OPERATING_CONFIG_VIEW',
    'FLIGHT_SCHEDULE_VIEW',
    'LOAD_CONTROL_VIEW'
  );

create or replace function private.current_is_observer()
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select (select auth.uid()) is not null
    and exists(
      select 1
      from application_security.user_global_roles ugr
      join application_security.roles r on r.role_id=ugr.role_id
      where ugr.user_id=(select auth.uid())
        and ugr.active
        and ugr.valid_from<=now()
        and (ugr.valid_until is null or ugr.valid_until>now())
        and r.active
        and r.role_scope='GLOBAL'
        and r.role_code='OBSERVER'
    )
    and not exists(
      select 1
      from application_security.permissions p
      where p.active
        and p.permission_code not in(
          'MASTER_DATA_VIEW',
          'CARRIER_CONFIG_VIEW',
          'FLEET_CONFIG_VIEW',
          'AIRCRAFT_CONFIG_VIEW',
          'OPERATING_CONFIG_VIEW',
          'FLIGHT_SCHEDULE_VIEW',
          'LOAD_CONTROL_VIEW'
        )
        and private.has_any_permission(p.permission_code)
    );
$$;

revoke all on function private.current_is_observer() from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".current_access_mode()
returns text
language sql
stable
set search_path=''
as $$
  select case when private.current_is_observer() then 'READ_ONLY' else 'STANDARD' end;
$$;

revoke all on function "Basic_Carrier_Record".current_access_mode() from public,anon;
grant execute on function "Basic_Carrier_Record".current_access_mode() to authenticated;

create or replace function "Basic_Carrier_Record".get_master_airport_configuration()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  can_edit boolean:=private.is_solution_administrator();
begin
  if not can_edit and not private.has_global_permission('MASTER_DATA_VIEW') then
    raise exception 'Master airport access required' using errcode='42501';
  end if;
  return jsonb_build_object(
    'canEdit',can_edit,
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
end;
$$;

revoke all on function "Basic_Carrier_Record".get_master_airport_configuration() from public,anon;
grant execute on function "Basic_Carrier_Record".get_master_airport_configuration() to authenticated;

notify pgrst,'reload schema';

commit;
