-- PostgREST 14 retries SQLSTATE 40001 indefinitely because PostgreSQL defines
-- it as a transient serialization failure. Optimistic-concurrency conflicts
-- are permanent for the submitted revision, so return HTTP 409 instead.
do $migration$
declare
  function_row record;
  function_ddl text;
begin
  for function_row in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'Basic_Carrier_Record'
      and p.prokind = 'f'
      and p.proname in (
        'save_carrier_crew_hold_baggage',
        'save_operational_load_plan'
      )
      and p.prosrc like '%40001%'
  loop
    function_ddl := replace(
      pg_get_functiondef(function_row.oid),
      '''40001''',
      '''PT409'''
    );
    execute function_ddl;
  end loop;
end
$migration$;
