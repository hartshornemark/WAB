-- Transaction-only role regression checks. Changes are always rolled back.
begin;
insert into application_security.organisations(organisation_id,organisation_name,organisation_type) values ('a5aa0000-0000-4000-8000-000000000001','Temporary carrier details verification','AIRLINE');
insert into application_security.organisation_users(organisation_id,user_id) values ('a5aa0000-0000-4000-8000-000000000001','b5c937a4-db85-4b47-bb59-23c99cc6799d');
insert into application_security.organisation_carrier_access(organisation_id,carrier_iata) values ('a5aa0000-0000-4000-8000-000000000001','ZZ');
insert into application_security.user_carrier_access(user_carrier_access_id,organisation_id,user_id,carrier_iata) values ('a5aa0000-0000-4000-8000-000000000002','a5aa0000-0000-4000-8000-000000000001','b5c937a4-db85-4b47-bb59-23c99cc6799d','ZZ');
insert into application_security.user_carrier_roles(user_carrier_access_id,role_id) select 'a5aa0000-0000-4000-8000-000000000002',role_id from application_security.roles where role_code='CONFIGURATION_EDITOR';
update application_security.user_global_roles set active=false where user_id='b5c937a4-db85-4b47-bb59-23c99cc6799d';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b5c937a4-db85-4b47-bb59-23c99cc6799d","role":"authenticated"}',true);
do $$ declare s jsonb; n int; begin
s:="Basic_Carrier_Record".get_carrier_details('ZZ');
if not (s->>'canView')::boolean or (s->>'canEdit')::boolean then raise exception 'FAIL editor capabilities %',s; end if;
begin perform "Basic_Carrier_Record".save_carrier_details('ZZ',s->>'revision',s->'values'); raise exception 'FAIL editor RPC'; exception when insufficient_privilege then null; end;
update "Basic_Carrier_Record"."Carrier_Contact_Data" set "City"='Forbidden' where "Carrier_IATA"='ZZ'; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL direct contact edit'; end if;
update "Basic_Carrier_Record"."Basic_Carrier_Data" set "Carrier_Unit_Weight_KG"=true where "Carrier_IATA"='ZZ'; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL direct basic edit'; end if;
end $$;
reset role;
update application_security.user_carrier_roles set role_id=(select role_id from application_security.roles where role_code='CARRIER_ADMINISTRATOR') where user_carrier_access_id='a5aa0000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ declare s jsonb; t jsonb; begin
s:="Basic_Carrier_Record".get_carrier_details('ZZ'); if not (s->>'canEdit')::boolean then raise exception 'FAIL carrier admin'; end if;
t:="Basic_Carrier_Record".save_carrier_details('ZZ',s->>'revision',s->'values');
if not (t->>'exists')::boolean then raise exception 'FAIL carrier save'; end if;
begin perform "Basic_Carrier_Record".save_carrier_details('XY','',s->'values'); raise exception 'FAIL cross carrier'; exception when insufficient_privilege then null; end;
end $$;
select 'PASS editor read-only and direct-write denial; carrier administrator save and cross-carrier denial' result;
rollback;
