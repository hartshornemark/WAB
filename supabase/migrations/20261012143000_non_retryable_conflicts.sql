-- SQLSTATE 40001 means a genuine serialization failure. The database/API
-- infrastructure is allowed to retry it automatically, so it must not be used
-- for application-level optimistic-lock conflicts. Expose those conflicts as
-- an explicit HTTP 409 instead.
do $migration$
declare
  routine record;
  definition text;
begin
  for routine in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prokind = 'f'
      and n.nspname in ('Basic_Carrier_Record', 'public')
      and pg_get_functiondef(p.oid) ilike '%40001%'
  loop
    definition := replace(pg_get_functiondef(routine.oid), '40001', 'PT409');
    execute definition;
  end loop;
end
$migration$;
