-- Transaction-only regression checks. All test data and role assignments roll back.
begin;
-- Privileged direct writes still obey letter-only and description constraints.
do $$ declare bad text; n integer; begin
foreach bad in array array['1','!','é','AB',''] loop
begin update "Basic_Carrier_Record"."MASTER_Class_Codes" set "Class_Code"=bad where "Class_Code"='F'; raise exception 'FAIL master accepted %',bad; exception when check_violation then null; end;
end loop;
for n in 1..4 loop
foreach bad in array array['1','!','é'] loop
begin execute format('update "Basic_Carrier_Record"."Carrier_Class_Codes" set %I=$1 where "Carrier_IATA"=''ZZ''','Carrier_Class_'||n||'_Code') using bad; raise exception 'FAIL carrier accepted %',bad; exception when check_violation then null; end;
end loop;
end loop;
begin update "Basic_Carrier_Record"."Carrier_Class_Codes" set "Carrier_Class_2_Code"="Carrier_Class_1_Code" where "Carrier_IATA"='ZZ'; raise exception 'FAIL direct duplicate'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Class_Codes" set "Carrier_Class_1_Name"=null where "Carrier_IATA"='ZZ'; raise exception 'FAIL unpaired class'; exception when check_violation then null; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b5c937a4-db85-4b47-bb59-23c99cc6799d","role":"authenticated"}',true);
do $$ declare s jsonb; t jsonb; initial jsonb; n integer; candidate jsonb; begin
s:="Basic_Carrier_Record".get_carrier_class_codes('ZZ'); initial:=s;
if not (s->>'canEdit')::boolean or jsonb_array_length(s->'rows')<>4 or jsonb_array_length(s->'defaults')<>0 then raise exception 'FAIL existing classes'; end if;
t:="Basic_Carrier_Record".save_carrier_class_codes('ZZ',s->>'revision','[{"code":"y","priority":4,"description":"Single class"}]');
if t->'rows' <> '[{"code":"Y","priority":4,"description":"Single class"}]'::jsonb then raise exception 'FAIL single class priority 4 %',t; end if;
if exists(select 1 from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"='ZZ' and "Carrier_Class_1_Code" is not null) then raise exception 'FAIL deleted slot retained'; end if;
begin perform "Basic_Carrier_Record".save_carrier_class_codes('ZZ',initial->>'revision',initial->'rows'); raise exception 'FAIL stale save'; exception when serialization_failure then null; end;
for candidate in select value from jsonb_array_elements('[[],[{"code":"1","priority":1,"description":"Bad"}],[{"code":"!","priority":1,"description":"Bad"}],[{"code":"F","priority":5,"description":"Bad"}],[{"code":"F","priority":1.5,"description":"Bad"}],[{"code":"F","priority":"1","description":"Bad"}],[{"code":"F","priority":1,"description":""}],[{"code":"F","priority":1,"description":"A"},{"code":"f","priority":2,"description":"B"}],[{"code":"F","priority":1,"description":"A"},{"code":"Y","priority":1,"description":"B"}]]'::jsonb) loop
begin perform "Basic_Carrier_Record".save_carrier_class_codes('ZZ',t->>'revision',candidate); raise exception 'FAIL invalid accepted %',candidate; exception when invalid_parameter_value then null; end;
end loop;
-- One, two, three and four retained classes all save; priority/code/name are independently editable.
for n in 1..4 loop
select jsonb_agg(jsonb_build_object('code',substr('FCWY',i,1),'priority',i,'description',repeat('x',64)) order by i) into candidate from generate_series(1,n) i;
s:="Basic_Carrier_Record".get_carrier_class_codes('ZZ');
t:="Basic_Carrier_Record".save_carrier_class_codes('ZZ',s->>'revision',candidate);
if jsonb_array_length(t->'rows')<>n then raise exception 'FAIL class count %',n; end if;
end loop;
s:="Basic_Carrier_Record".get_carrier_class_codes('ZZ');
t:="Basic_Carrier_Record".save_carrier_class_codes('ZZ',s->>'revision','[{"code":"C","priority":1,"description":"Business changed"},{"code":"F","priority":2,"description":"First changed"}]');
if t->'rows'->0->>'code'<>'C' or t->'rows'->1->>'code'<>'F' then raise exception 'FAIL priority swap'; end if;
delete from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"='ZZ';
s:="Basic_Carrier_Record".get_carrier_class_codes('ZZ');
if jsonb_array_length(s->'rows')<>0 or jsonb_array_length(s->'defaults')<>4 then raise exception 'FAIL master defaults'; end if;
t:="Basic_Carrier_Record".save_carrier_class_codes('ZZ',s->>'revision',s->'defaults');
if jsonb_array_length(t->'rows')<>4 then raise exception 'FAIL initial insert'; end if;
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
s:="Basic_Carrier_Record".get_carrier_class_codes('ZZ');
if not (s->>'canView')::boolean or (s->>'canEdit')::boolean then raise exception 'FAIL editor read-only'; end if;
begin perform "Basic_Carrier_Record".save_carrier_class_codes('ZZ',s->>'revision',s->'rows'); raise exception 'FAIL editor RPC'; exception when insufficient_privilege then null; end;
update "Basic_Carrier_Record"."Carrier_Class_Codes" set "Carrier_Class_1_Name"='Forbidden' where "Carrier_IATA"='ZZ'; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL editor update'; end if;
delete from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"='ZZ'; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL editor delete'; end if;
begin insert into "Basic_Carrier_Record"."Carrier_Class_Codes"("Carrier_IATA","Carrier_Class_1_Code","Carrier_Class_1_Name") values ('ZZ','X','Forbidden'); raise exception 'FAIL editor insert'; exception when insufficient_privilege then null; end;
begin update "Basic_Carrier_Record"."MASTER_Class_Codes" set "Class_Code_Name"='Forbidden' where "Class_Code"='F'; raise exception 'FAIL master update'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update application_security.user_carrier_roles set role_id=(select role_id from application_security.roles where role_code='CARRIER_ADMINISTRATOR') where user_carrier_access_id='a5aa0000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ declare s jsonb; t jsonb; begin
s:="Basic_Carrier_Record".get_carrier_class_codes('ZZ'); if not (s->>'canEdit')::boolean then raise exception 'FAIL carrier administrator'; end if;
t:="Basic_Carrier_Record".save_carrier_class_codes('ZZ',s->>'revision','[{"code":"C","priority":3,"description":"Business"}]');
if jsonb_array_length(t->'rows')<>1 then raise exception 'FAIL carrier save/delete'; end if;
begin perform "Basic_Carrier_Record".save_carrier_class_codes('XY','',t->'rows'); raise exception 'FAIL cross carrier RPC'; exception when insufficient_privilege then null; end;
begin insert into "Basic_Carrier_Record"."Carrier_Class_Codes"("Carrier_IATA","Carrier_Class_1_Code","Carrier_Class_1_Name") values ('XY','X','Forbidden'); raise exception 'FAIL cross carrier insert'; exception when insufficient_privilege then null; end;
begin update "Basic_Carrier_Record"."Carrier_Class_Codes" set "Carrier_IATA"='XY' where "Carrier_IATA"='ZZ'; raise exception 'FAIL identity reassignment'; exception when insufficient_privilege then null; end;
delete from "Basic_Carrier_Record"."Carrier_Class_Codes" where "Carrier_IATA"='ZZ';
s:="Basic_Carrier_Record".get_carrier_class_codes('ZZ'); if jsonb_array_length(s->'defaults')<>4 then raise exception 'FAIL carrier defaults'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
set local role authenticated;
do $$ declare s jsonb; begin
s:="Basic_Carrier_Record".get_carrier_class_codes('ZZ'); if (s->>'canView')::boolean or jsonb_array_length(s->'defaults')<>0 then raise exception 'FAIL unassigned read'; end if;
begin perform "Basic_Carrier_Record".save_carrier_class_codes('ZZ','','[{"code":"Y","priority":4,"description":"Y"}]'); raise exception 'FAIL unassigned save'; exception when insufficient_privilege then null; end;
if exists(select 1 from "Basic_Carrier_Record"."MASTER_Class_Codes") then raise exception 'FAIL unassigned master read'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
begin perform "Basic_Carrier_Record".get_carrier_class_codes('ZZ'); raise exception 'FAIL anon function'; exception when insufficient_privilege then null; end;
begin perform 1 from "Basic_Carrier_Record"."Carrier_Class_Codes"; raise exception 'FAIL anon carrier table'; exception when insufficient_privilege then null; end;
begin perform 1 from "Basic_Carrier_Record"."MASTER_Class_Codes"; raise exception 'FAIL anon master table'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS class constraints, master defaults, 1–4 classes, deletion, all-field edits, priorities, stale saves and role/cross-carrier/anonymous protections' as result;
rollback;
