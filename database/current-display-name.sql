-- Applied with explicit user approval: return only the signed-in active account's own display name.
begin;
create function private.current_display_name() returns text
language sql stable security definer set search_path='' as $$
select nullif(btrim(display_name),'') from application_security.application_users
where (select auth.uid()) is not null and user_id=(select auth.uid()) and active;
$$;
revoke all on function private.current_display_name() from public,anon;
grant execute on function private.current_display_name() to authenticated;
create function "Basic_Carrier_Record".current_display_name() returns text
language sql stable security invoker set search_path='' as $$
select private.current_display_name();
$$;
revoke all on function "Basic_Carrier_Record".current_display_name() from public,anon;
grant execute on function "Basic_Carrier_Record".current_display_name() to authenticated;
notify pgrst,'reload schema';
commit;
