begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b5c937a4-db85-4b47-bb59-23c99cc6799d","role":"authenticated"}',true);
do $$ declare s jsonb; r jsonb; oldrev text; begin
s:="Basic_Carrier_Record".get_carrier_ulds('ZZ');
if not (s->>'canEdit')::boolean or s->'rows'->0->>'tare'<>'90.000000' then raise exception 'FAIL existing values/access'; end if;
r:=s->'rows';oldrev:=s->>'revision';
s:="Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',r||'[{"code":"AVE","type":"LD3","isCustom":false,"isDefault":false,"tare":"100","maximum":"1588","volume":"4.3","remarks":"verification","inventory":[]}]'::jsonb);
if jsonb_array_length(s->'rows')<>jsonb_array_length(r)+1 then raise exception 'FAIL adoption';end if;
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',oldrev,r);raise exception 'FAIL stale';exception when serialization_failure then null;end;
r:=jsonb_set(s->'rows','{0,isDefault}','false');r:=jsonb_set(r,'{1,isDefault}','true');
s:="Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',r);
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(r,'{1,isDefault}','false'));raise exception 'FAIL missing default';exception when check_violation then null;end;
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(r,'{0,isDefault}','true'));raise exception 'FAIL duplicate default';exception when unique_violation then null;end;
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(r,'{0,maximum}','"1"'));raise exception 'FAIL weight order';exception when check_violation then null;end;
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(r,'{0,volume}','"0"'));raise exception 'FAIL volume';exception when check_violation then null;end;
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(r,'{0,code}','"XXX"'));raise exception 'FAIL master';exception when foreign_key_violation then null;end;
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(r,'{0,tare}','"90.5"'));raise exception 'FAIL fractional tare';exception when check_violation then null;end;
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(r,'{0,maximum}','"1588.5"'));raise exception 'FAIL fractional maximum';exception when check_violation then null;end;
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',jsonb_set(r,'{0,volume}','"4.301"'));raise exception 'FAIL volume precision';exception when check_violation then null;end;
begin update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "Carrier_IATA"='XY' where "Carrier_IATA"='ZZ';raise exception 'FAIL identity';exception when insufficient_privilege then null;end;
end $$;
set constraints all immediate;
set constraints all deferred;
update "Basic_Carrier_Record"."Basic_Carrier_Data" set "Carrier_Unit_Weight_KG"=false,"Carrier_Unit_Weight_LB"=true,"Carrier_Unit_Volume_m3"=false,"Carrier_Unit_Volume_ft3"=true where "Carrier_IATA"='ZZ';
do $$ begin
if not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"='ZZ' and "ULD_ID"='AKE' and "ULD_Tare_Weight"=round(90/0.45359237,0) and "ULD_Max_Volume"=round(4.3/0.028316846592,2)) then raise exception 'FAIL conversion';end if;
end $$;
update "Basic_Carrier_Record"."Basic_Carrier_Data" set "Carrier_Unit_Weight_KG"=true,"Carrier_Unit_Weight_LB"=false,"Carrier_Unit_Volume_m3"=true,"Carrier_Unit_Volume_ft3"=false where "Carrier_IATA"='ZZ';
reset role;
insert into application_security.organisations(organisation_id,organisation_name,organisation_type) values ('a5aa0000-0000-4000-8000-000000000001','Temporary carrier details verification','AIRLINE');
insert into application_security.organisation_users(organisation_id,user_id) values ('a5aa0000-0000-4000-8000-000000000001','b5c937a4-db85-4b47-bb59-23c99cc6799d');
insert into application_security.organisation_carrier_access(organisation_id,carrier_iata) values ('a5aa0000-0000-4000-8000-000000000001','ZZ');
insert into application_security.user_carrier_access(user_carrier_access_id,organisation_id,user_id,carrier_iata) values ('a5aa0000-0000-4000-8000-000000000002','a5aa0000-0000-4000-8000-000000000001','b5c937a4-db85-4b47-bb59-23c99cc6799d','ZZ');
insert into application_security.user_carrier_roles(user_carrier_access_id,role_id) select 'a5aa0000-0000-4000-8000-000000000002',role_id from application_security.roles where role_code='CONFIGURATION_EDITOR';
update application_security.user_global_roles set active=false where user_id='b5c937a4-db85-4b47-bb59-23c99cc6799d';

set local role authenticated;
do $$ declare s jsonb;n int; begin
s:="Basic_Carrier_Record".get_carrier_ulds('ZZ');
if not (s->>'canView')::boolean or (s->>'canEdit')::boolean then raise exception 'FAIL editor access';end if;
update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "ULD_Tare_Weight"=1;get diagnostics n=row_count;if n<>0 then raise exception 'FAIL editor write';end if;
delete from "Basic_Carrier_Record"."Carrier_ULD_Specifications";get diagnostics n=row_count;if n<>0 then raise exception 'FAIL editor delete';end if;
begin perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',s->'rows');raise exception 'FAIL editor RPC';exception when insufficient_privilege then null;end;
end $$;
reset role;
update application_security.user_carrier_roles set role_id=(select role_id from application_security.roles where role_code='CARRIER_ADMINISTRATOR') where user_carrier_access_id='a5aa0000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ declare s jsonb;begin
s:="Basic_Carrier_Record".get_carrier_ulds('ZZ');
perform "Basic_Carrier_Record".save_carrier_ulds('ZZ',s->>'revision',s->'rows');
begin perform "Basic_Carrier_Record".save_carrier_ulds('XY','','[]');raise exception 'FAIL cross carrier';exception when insufficient_privilege then null;end;
end $$;
set constraints all immediate;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
set local role authenticated;
do $$ declare s jsonb;begin
s:="Basic_Carrier_Record".get_carrier_ulds('ZZ');if (s->>'canView')::boolean or jsonb_array_length(s->'rows')<>0 or jsonb_array_length(s->'master')<>0 then raise exception 'FAIL unassigned';end if;
end $$;
reset role;set local role anon;
do $$ begin
begin perform "Basic_Carrier_Record".get_carrier_ulds('ZZ');raise exception 'FAIL anonymous';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS B5 preservation, adoption, defaults, stale edits, validation, unit conversion, SA/CA permissions, editor/cross-carrier/unassigned/anonymous denials' as result;
rollback;
