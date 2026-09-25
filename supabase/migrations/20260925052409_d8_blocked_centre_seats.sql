begin;
-- :B preserves three physical spaces per group with the centre unavailable.
-- Plain groupings retain their existing meaning and usable-seat counts.
alter table "Basic_Carrier_Record"."Aircraft_Cabin_Areas"
 drop constraint "Cabin_Area_Seat_Grouping_check",
 add constraint "Cabin_Area_Seat_Grouping_check" check ("Seat_Grouping_Default" ~ '^([1-9](-[1-9]){0,3}|3(-3){0,3}:B)$');
alter table "Basic_Carrier_Record"."Aircraft_Seat_Rows"
 drop constraint "Seat_Row_Grouping_check",
 add constraint "Seat_Row_Grouping_check" check ("Seat_Grouping_Override" ~ '^([1-9](-[1-9]){0,3}|3(-3){0,3}:B)$');
create or replace function private.d8_grouping_seats(p_grouping text) returns integer
language plpgsql immutable strict security invoker set search_path='' as $$
begin
 if p_grouping !~ '^([1-9](-[1-9]){0,3}|3(-3){0,3}:B)$' then raise exception 'Invalid seat grouping' using errcode='23514';end if;
 return (select sum(value::integer - case when right(p_grouping,2)=':B' then 1 else 0 end)::integer
 from unnest(string_to_array(replace(p_grouping,':B',''),'-')) value);
end $$;
revoke all on function private.d8_grouping_seats(text) from public,anon,authenticated;
comment on column "Basic_Carrier_Record"."Aircraft_Seat_Rows"."Seat_Grouping_Override" is 'Null inherits area default. Hyphens separate physical seat groups; :B suffix blocks the centre of each three-seat group. Usable seats exclude blocked centres.';
commit;
