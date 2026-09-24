begin;

-- Solution Administrators manage global aircraft identities and must also be
-- able to create and maintain a carrier's C1 aircraft configuration.
insert into application_security.role_permissions (role_id, permission_id)
select r.role_id, p.permission_id
from application_security.roles r
cross join application_security.permissions p
where r.role_code = 'SOLUTION_ADMINISTRATOR'
  and r.active
  and p.active
  and p.permission_code in (
    'AIRCRAFT_CONFIG_VIEW',
    'AIRCRAFT_CONFIG_CREATE',
    'AIRCRAFT_CONFIG_EDIT',
    'AIRCRAFT_CONFIG_DELETE'
  )
on conflict do nothing;

commit;
