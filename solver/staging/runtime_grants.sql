-- Last file in the reviewed single-transaction installation on current Supabase.
-- The role starts NOLOGIN; enable login/set password separately in a secure session.
do $$ begin
 if current_database()<>'postgres' or not exists(select 1 from pg_roles
   where rolname='capacity_benchmark' and not rolsuper and not rolcreatedb
   and not rolcreaterole and not rolbypassrls and not rolinherit) then
  raise exception 'Expected restricted benchmark role on current Supabase database';
 end if;
end $$;
revoke all on schema capacity_reference from public, anon, authenticated, service_role;
revoke all on all functions in schema capacity_reference from public, anon, authenticated, service_role;
grant usage on schema capacity_reference to capacity_benchmark;
grant execute on all functions in schema capacity_reference to capacity_benchmark;
alter role capacity_benchmark in database postgres set default_transaction_read_only=on;
alter role capacity_benchmark in database postgres set statement_timeout='60s';
alter role capacity_benchmark in database postgres set lock_timeout='1s';
-- No operational table privileges, schema CREATE or role memberships are granted.

-- Pin only the new private functions; do not change frozen calculation bodies.
do $$ declare fn text; begin
 for fn in select p.oid::regprocedure::text from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace where n.nspname='capacity_reference'
 loop execute format('alter function %s set search_path = pg_catalog',fn); end loop;
end $$;
