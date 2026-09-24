-- Transaction-only B2 checks; test writes and role fixtures roll back.
begin;
do $$ begin
begin update "Basic_Carrier_Record"."Carrier_Crew_Weights" set "Crew_Weight_Flight_Deck_Male"=0 where "Carrier_IATA"='ZZ'; raise exception 'FAIL direct zero crew'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Crew_Weights" set "Crew_Bag_Weight_Cabin_LHL"=-1 where "Carrier_IATA"='ZZ'; raise exception 'FAIL direct negative baggage'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Crew_Weights" set "Crew_Weight_Incude_Handbaggage"=false,"Crew_Hand_Bag_Weight_FlightDeck"=null where "Carrier_IATA"='ZZ'; raise exception 'FAIL direct missing hand baggage'; exception when check_violation then null; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b5c937a4-db85-4b47-bb59-23c99cc6799d","role":"authenticated"}',true);
do $$ declare s jsonb; t jsonb; v jsonb; initial jsonb; change jsonb; begin
s:="Basic_Carrier_Record".get_carrier_crew_weights('ZZ'); s:=jsonb_set(s,'{values}',(s->'values')||'{"allFlights":false,"longhaul":true,"shorthaul":true}'::jsonb); initial:=s;
if not (s->>'canEdit')::boolean or not (s->>'exists')::boolean or s->>'unit'<>'KG' then raise exception 'FAIL initial snapshot %',s; end if;
for change in select value from jsonb_array_elements('[{"flightDeckMale":0},{"cabinFemale":null},{"cabinMale":75.5},{"cabinShort":-1},{"flightDeckHand":2147483648},{"includesHandBaggage":"false"},{"includesHandBaggage":false,"flightDeckHand":null,"cabinHand":null}]') loop
begin perform "Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',(s->'values')||change); raise exception 'FAIL invalid weights %',change; exception when invalid_parameter_value then null; end;
end loop;
t:="Basic_Carrier_Record".get_carrier_crew_weights('ZZ'); if t->>'revision'<>s->>'revision' then raise exception 'FAIL invalid save changed data'; end if;
v := (s->'values') || '{"includesHandBaggage":false,"flightDeckHand":5,"cabinHand":4,"flightDeckOther":null,"cabinOther":0}'::jsonb;
t:="Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',v);
if t->'values'<>v then raise exception 'FAIL separate baggage roundtrip'; end if;
begin perform "Basic_Carrier_Record".save_carrier_crew_weights('ZZ',initial->>'revision',initial->'values'); raise exception 'FAIL stale save'; exception when serialization_failure then null; end;
s:=t; v:=(t->'values')||'{"includesHandBaggage":true}'::jsonb;
t:="Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',v);
if t->'values'->>'flightDeckHand'<>'5' or not (t->'values'->>'includesHandBaggage')::boolean then raise exception 'FAIL retained inactive baggage'; end if;
s:=t;
update "Basic_Carrier_Record"."Basic_Carrier_Data" set "Carrier_Unit_Weight_KG"=false,"Carrier_Unit_Weight_LB"=true where "Carrier_IATA"='ZZ';
begin perform "Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',s->'values'); raise exception 'FAIL stale unit'; exception when serialization_failure then null; end;
update "Basic_Carrier_Record"."Basic_Carrier_Data" set "Carrier_Unit_Weight_KG"=true,"Carrier_Unit_Weight_LB"=false where "Carrier_IATA"='ZZ';
delete from "Basic_Carrier_Record"."Carrier_Crew_Weights" where "Carrier_IATA"='ZZ';
s:="Basic_Carrier_Record".get_carrier_crew_weights('ZZ'); if (s->>'exists')::boolean or s->'values'->>'flightDeckMale' is not null then raise exception 'FAIL no saved row'; end if;
t:="Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',initial->'values'); if not (t->>'exists')::boolean then raise exception 'FAIL initial insert'; end if;
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
s:="Basic_Carrier_Record".get_carrier_crew_weights('ZZ'); if not (s->>'canView')::boolean or (s->>'canEdit')::boolean then raise exception 'FAIL editor read-only'; end if;
begin perform "Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',s->'values'); raise exception 'FAIL editor save'; exception when insufficient_privilege then null; end;
update "Basic_Carrier_Record"."Carrier_Crew_Weights" set "Crew_Weight_Cabin_Male"=1 where "Carrier_IATA"='ZZ'; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL editor direct update'; end if;
delete from "Basic_Carrier_Record"."Carrier_Crew_Weights" where "Carrier_IATA"='ZZ'; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL editor delete'; end if;
begin insert into "Basic_Carrier_Record"."Carrier_Crew_Weights"("Carrier_IATA") values ('ZZ'); raise exception 'FAIL editor insert'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update application_security.user_carrier_roles set role_id=(select role_id from application_security.roles where role_code='CARRIER_ADMINISTRATOR') where user_carrier_access_id='a5aa0000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ declare s jsonb; t jsonb; begin
s:="Basic_Carrier_Record".get_carrier_crew_weights('ZZ'); if not (s->>'canEdit')::boolean then raise exception 'FAIL carrier admin'; end if;
t:="Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',s->'values');
begin perform "Basic_Carrier_Record".save_carrier_crew_weights('XY','',s->'values'); raise exception 'FAIL cross carrier RPC'; exception when insufficient_privilege then null; end;
begin insert into "Basic_Carrier_Record"."Carrier_Crew_Weights"("Carrier_IATA") values ('XY'); raise exception 'FAIL cross carrier insert'; exception when insufficient_privilege then null; end;
begin update "Basic_Carrier_Record"."Carrier_Crew_Weights" set "Carrier_IATA"='XY' where "Carrier_IATA"='ZZ'; raise exception 'FAIL identity reassignment'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
set local role authenticated;
do $$ declare s jsonb; begin
s:="Basic_Carrier_Record".get_carrier_crew_weights('ZZ'); if (s->>'canView')::boolean or s->'values'->>'flightDeckMale' is not null then raise exception 'FAIL unassigned read'; end if;
begin perform "Basic_Carrier_Record".save_carrier_crew_weights('ZZ','','{}'); raise exception 'FAIL unassigned save'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
begin perform "Basic_Carrier_Record".get_carrier_crew_weights('ZZ'); raise exception 'FAIL anon RPC'; exception when insufficient_privilege then null; end;
begin perform 1 from "Basic_Carrier_Record"."Carrier_Crew_Weights"; raise exception 'FAIL anon table'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS crew constraints, conditional hand baggage, retained inactive values, null versus zero, stale data/unit, insert, SA/CA save and editor/cross-carrier/anonymous denials' as result;
rollback;
