begin;

create or replace function private.has_carrier_permission(
  p_carrier_iata text,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select (
      private.current_is_observer()
      and p_permission_code in(
        'CARRIER_CONFIG_VIEW',
        'FLEET_CONFIG_VIEW',
        'AIRCRAFT_CONFIG_VIEW',
        'OPERATING_CONFIG_VIEW',
        'FLIGHT_SCHEDULE_VIEW',
        'LOAD_CONTROL_VIEW'
      )
    )
    or (
      (select auth.uid()) is not null
      and exists (
        select 1
        from application_security.application_users au
        join application_security.user_carrier_access uca
          on uca.user_id=au.user_id
         and uca.carrier_iata=p_carrier_iata
        join application_security.organisation_users ou
          on ou.organisation_id=uca.organisation_id
         and ou.user_id=uca.user_id
        join application_security.organisation_carrier_access oca
          on oca.organisation_id=uca.organisation_id
         and oca.carrier_iata=uca.carrier_iata
        join application_security.user_carrier_roles ucr
          on ucr.user_carrier_access_id=uca.user_carrier_access_id
        join application_security.roles r
          on r.role_id=ucr.role_id
        join application_security.role_permissions rp
          on rp.role_id=r.role_id
        join application_security.permissions p
          on p.permission_id=rp.permission_id
        where au.user_id=(select auth.uid())
          and au.active
          and uca.active
          and uca.valid_from<=now()
          and (uca.valid_until is null or uca.valid_until>=now())
          and ou.active
          and ou.valid_from<=now()
          and (ou.valid_until is null or ou.valid_until>=now())
          and oca.active
          and oca.valid_from<=now()
          and (oca.valid_until is null or oca.valid_until>=now())
          and ucr.active
          and ucr.valid_from<=now()
          and (ucr.valid_until is null or ucr.valid_until>=now())
          and r.active
          and r.role_scope='CARRIER'
          and p.active
          and p.permission_code=p_permission_code
      )
    );
$$;

revoke all on function private.has_carrier_permission(text,text) from public,anon;
grant execute on function private.has_carrier_permission(text,text) to authenticated;

commit;
