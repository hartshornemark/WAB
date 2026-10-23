-- Preparation only. First file in the SINGLE TRANSACTION installation below.
-- Run as the schema administrator of the approved current Supabase project.
-- Existing schema/role names cause a complete abort; never overwrite unknown objects.
do $$ begin
 if current_database()<>'postgres' then raise exception 'Expected current Supabase postgres database'; end if;
 if exists(select 1 from pg_namespace where nspname='capacity_reference') then
  raise exception 'capacity_reference already exists: review ownership/content before proceeding';
 end if;
 if exists(select 1 from pg_roles where rolname='capacity_benchmark') then
  raise exception 'capacity_benchmark already exists: review before proceeding';
 end if;
end $$;
create role capacity_benchmark nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
