-- All fixture data and test edits are rolled back.
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b5c937a4-db85-4b47-bb59-23c99cc6799d","role":"authenticated"}',true);
do $$ declare s jsonb; t jsonb; begin
s:="Basic_Carrier_Record".get_carrier_commodity_codes('ZZ');
if not (s->>'canEdit')::boolean or jsonb_array_length(s->'defaults')<>7 then raise exception 'FAIL administrator defaults'; end if;
t:="Basic_Carrier_Record".save_carrier_commodity_codes('ZZ',s->>'revision',s->'defaults');
if jsonb_array_length(t->'rows')<>7 or jsonb_array_length(t->'defaults')<>0 then raise exception 'FAIL full set save'; end if;
begin perform "Basic_Carrier_Record".save_carrier_commodity_codes('ZZ',s->>'revision',s->'defaults'); raise exception 'FAIL stale save'; exception when serialization_failure then null; end;
begin perform "Basic_Carrier_Record".save_carrier_commodity_codes('ZZ',t->>'revision','[{"code":"B","description":"Baggage"},{"code":"b","description":"Duplicate"}]'); raise exception 'FAIL duplicate save'; exception when invalid_parameter_value then null; end;
begin perform "Basic_Carrier_Record".save_carrier_commodity_codes('ZZ',t->>'revision','[]'); raise exception 'FAIL empty save'; exception when invalid_parameter_value then null; end;
s:="Basic_Carrier_Record".save_carrier_commodity_codes('ZZ',t->>'revision','[{"code":"B","description":"Test baggage"}]');
if jsonb_array_length(s->'rows')<>1 or s->'rows'->0->>'description'<>'Test baggage' then raise exception 'FAIL replace'; end if;
end $$;
reset role;
insert into application_security.organisations(organisation_id,organisation_name,organisation_type) values ('a5aa0000-0000-4000-8000-000000000001','Temporary carrier details verification','AIRLINE');
insert into application_security.organisation_users(organisation_id,user_id) values ('a5aa0000-0000-4000-8000-000000000001','b5c937a4-db85-4b47-bb59-23c99cc6799d');
insert into application_security.organisation_carrier_access(organisation_id,carrier_iata) values ('a5aa0000-0000-4000-8000-000000000001','ZZ');
insert into application_security.user_carrier_access(user_carrier_access_id,organisation_id,user_id,carrier_iata) values ('a5aa0000-0000-4000-8000-000000000002','a5aa0000-0000-4000-8000-000000000001','b5c937a4-db85-4b47-bb59-23c99cc6799d','ZZ');
insert into application_security.user_carrier_roles(user_carrier_access_id,role_id) select 'a5aa0000-0000-4000-8000-000000000002',role_id from application_security.roles where role_code='CONFIGURATION_EDITOR';
update application_security.user_global_roles set active=false where user_id='b5c937a4-db85-4b47-bb59-23c99cc6799d';
set local role authenticated;
do $$ declare s jsonb; n integer; begin
s:="Basic_Carrier_Record".get_carrier_commodity_codes('ZZ');
if not (s->>'canView')::boolean or (s->>'canEdit')::boolean or jsonb_array_length(s->'rows')<>1 then raise exception 'FAIL editor read'; end if;
begin perform "Basic_Carrier_Record".save_carrier_commodity_codes('ZZ',s->>'revision',s->'rows'); raise exception 'FAIL editor RPC'; exception when insufficient_privilege then null; end;
begin insert into "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" values ('ZZ','Q','Forbidden'); raise exception 'FAIL editor insert'; exception when insufficient_privilege then null; end;
update "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" set "Commodity_Description"='Forbidden' where "Carrier_IATA"='ZZ'; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL editor update'; end if;
delete from "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" where "Carrier_IATA"='ZZ'; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL editor delete'; end if;
end $$;
reset role;
update application_security.user_carrier_roles set role_id=(select role_id from application_security.roles where role_code='CARRIER_ADMINISTRATOR') where user_carrier_access_id='a5aa0000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ declare s jsonb; t jsonb; begin
s:="Basic_Carrier_Record".get_carrier_commodity_codes('ZZ');
if not (s->>'canEdit')::boolean then raise exception 'FAIL carrier admin'; end if;
t:="Basic_Carrier_Record".save_carrier_commodity_codes('ZZ',s->>'revision',s->'rows');
begin perform "Basic_Carrier_Record".save_carrier_commodity_codes('XY','',s->'rows'); raise exception 'FAIL cross-carrier save'; exception when insufficient_privilege then null; end;
begin insert into "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" values ('XY','Q','Forbidden'); raise exception 'FAIL cross-carrier insert'; exception when insufficient_privilege then null; end;
begin update "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" set "Carrier_IATA"='XY' where "Carrier_IATA"='ZZ'; raise exception 'FAIL identity reassignment'; exception when insufficient_privilege then null; end;
delete from "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes" where "Carrier_IATA"='ZZ';
s:="Basic_Carrier_Record".get_carrier_commodity_codes('ZZ'); if jsonb_array_length(s->'defaults')<>7 then raise exception 'FAIL carrier admin defaults'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
set local role authenticated;
do $$ declare s jsonb; begin
s:="Basic_Carrier_Record".get_carrier_commodity_codes('ZZ'); if (s->>'canView')::boolean or jsonb_array_length(s->'defaults')<>0 then raise exception 'FAIL unassigned access'; end if;
begin perform "Basic_Carrier_Record".save_carrier_commodity_codes('ZZ','','[{"code":"B","description":"B"}]'); raise exception 'FAIL unassigned save'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
begin perform "Basic_Carrier_Record".get_carrier_commodity_codes('ZZ'); raise exception 'FAIL anon RPC'; exception when insufficient_privilege then null; end;
begin perform 1 from "Basic_Carrier_Record"."Carrier_Unique_Commodity_Codes"; raise exception 'FAIL anon table'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: defaults, full save, replacement, validation, stale-save rejection, SA/CA access, editor read-only, cross-carrier and anonymous denial' as result;
rollback;
