-- Preparation only. Apply as the owner of the NEW capacity_staging_reference DB.
-- First create the NORMAL/non-admin capacity_reader account in DigitalOcean.
-- Runtime never receives the owner connection string.
do $$ begin
 if current_database()<>'capacity_staging_reference' then
  raise exception 'Refusing to configure a shared/application database';
 end if;
 if not exists(select 1 from pg_roles where rolname='capacity_reader' and not rolsuper and not rolcreatedb and not rolcreaterole) then
  raise exception 'Create a restricted capacity_reader account first';
 end if;
end $$;
revoke all on schema capacity_reference from public;
revoke execute on all functions in schema capacity_reference from public;
grant usage on schema capacity_reference to capacity_reader;
grant execute on all functions in schema capacity_reference to capacity_reader;
alter role capacity_reader in database capacity_staging_reference set default_transaction_read_only=on;
