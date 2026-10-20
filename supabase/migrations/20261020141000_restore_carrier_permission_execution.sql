begin;

grant execute on function private.has_carrier_permission(text,text) to authenticated;

commit;
