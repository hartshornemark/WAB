-- Proposed commodity editor access and atomic-save API. No rows are seeded by this change.
begin;
alter table "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" from public, anon;
grant select, insert, update, delete on "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" to authenticated;
create function private.can_view_carrier_commodities(p_iata text) returns boolean
language sql stable security invoker set search_path = '' as $$
select auth.uid() is not null
and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata)
and (private.can_edit_carrier_details(p_iata) or private.has_carrier_permission(p_iata,'CARRIER_CONFIG_VIEW'));
$$;
revoke all on function private.can_view_carrier_commodities(text) from public, anon;
grant execute on function private.can_view_carrier_commodities(text) to authenticated;
create policy commodity_read on "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" for select to authenticated using (private.can_view_carrier_commodities("Carrier_IATA"));
create policy commodity_insert on "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" for insert to authenticated with check (private.can_edit_carrier_details("Carrier_IATA"));
create policy commodity_update on "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" for update to authenticated using (private.can_edit_carrier_details("Carrier_IATA")) with check (private.can_edit_carrier_details("Carrier_IATA"));
create policy commodity_delete on "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" for delete to authenticated using (private.can_edit_carrier_details("Carrier_IATA"));
-- Read access to defaults follows existing carrier membership; master editing stays unchanged.
create policy commodity_defaults_read on "Basic_Carrier_Record"."MASTER_Commodity_Codes" for select to authenticated using (
exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" m where private.can_view_carrier_commodities(m."Carrier_IATA")));
create function "Basic_Carrier_Record".get_carrier_commodity_codes(p_iata text) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare v_rows jsonb; v_revision text; v_defaults jsonb := '[]';
begin
if not private.can_view_carrier_commodities(p_iata) then
return jsonb_build_object('canView',false,'canEdit',false,'revision','','rows','[]'::jsonb,'defaults','[]'::jsonb);
end if;
select coalesce(jsonb_agg(jsonb_build_object('code',"Commodity_Code",'description',"Commodity_Description") order by "Commodity_Code"),'[]'::jsonb),
md5(coalesce(string_agg(jsonb_build_array("Commodity_Code","Commodity_Description",xmin::text)::text,',' order by "Commodity_Code"),''))
into v_rows,v_revision from "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" where "Carrier_IATA"=p_iata;
if jsonb_array_length(v_rows)=0 then
select coalesce(jsonb_agg(jsonb_build_object('code',"Commodity_Code",'description',"Commodity_Description") order by "Commodity_Code"),'[]'::jsonb)
into v_defaults from "Basic_Carrier_Record"."MASTER_Commodity_Codes";
end if;
return jsonb_build_object('canView',true,'canEdit',private.can_edit_carrier_details(p_iata),'revision',v_revision,'rows',v_rows,'defaults',v_defaults);
end $$;
create function "Basic_Carrier_Record".save_carrier_commodity_codes(p_iata text,p_revision text,p_rows jsonb) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare v_snapshot jsonb; v_row jsonb; v_code text; v_description text; v_seen text[] := '{}'; v_clean jsonb := '[]';
begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501'; end if;
if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Invalid codes' using errcode='22023'; end if;
if jsonb_array_length(p_rows) not between 1 and 200 then raise exception 'Invalid list size' using errcode='22023'; end if;
for v_row in select value from jsonb_array_elements(p_rows) loop
if jsonb_typeof(v_row)<>'object' or jsonb_typeof(v_row->'code') is distinct from 'string' or jsonb_typeof(v_row->'description') is distinct from 'string' then raise exception 'Invalid row' using errcode='22023'; end if;
v_code := upper(btrim(v_row->>'code')); v_description := btrim(v_row->>'description');
if v_code !~ '^[A-Z0-9]{1,2}$' or char_length(v_description) not between 1 and 64 or v_description ~ '[[:cntrl:]]' or v_code=any(v_seen) then raise exception 'Invalid or duplicate code' using errcode='22023'; end if;
v_seen := array_append(v_seen,v_code); v_clean := v_clean || jsonb_build_array(jsonb_build_object('code',v_code,'description',v_description));
end loop;
perform pg_advisory_xact_lock(hashtextextended('carrier-commodities:'||p_iata,0));
perform 1 from "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" where "Carrier_IATA"=p_iata for update;
v_snapshot := "Basic_Carrier_Record".get_carrier_commodity_codes(p_iata);
if p_revision is distinct from v_snapshot->>'revision' then raise exception 'Codes changed' using errcode='40001'; end if;
delete from "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" where "Carrier_IATA"=p_iata;
insert into "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes"("Carrier_IATA","Commodity_Code","Commodity_Description")
select p_iata,value->>'code',value->>'description' from jsonb_array_elements(v_clean);
return "Basic_Carrier_Record".get_carrier_commodity_codes(p_iata);
exception when unique_violation then raise exception 'Codes changed' using errcode='40001';
end $$;
revoke all on function "Basic_Carrier_Record".get_carrier_commodity_codes(text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_carrier_commodity_codes(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_commodity_codes(text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_carrier_commodity_codes(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
