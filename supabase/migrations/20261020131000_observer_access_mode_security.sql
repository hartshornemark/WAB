begin;

create or replace function "Basic_Carrier_Record".current_access_mode()
returns text
language sql
stable
security definer
set search_path=''
as $$
  select case when private.current_is_observer() then 'READ_ONLY' else 'STANDARD' end;
$$;

revoke all on function "Basic_Carrier_Record".current_access_mode() from public,anon;
grant execute on function "Basic_Carrier_Record".current_access_mode() to authenticated;

commit;
