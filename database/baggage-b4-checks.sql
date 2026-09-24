begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b5c937a4-db85-4b47-bb59-23c99cc6799d","role":"authenticated"}',true);
do $$ begin
if not exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" where "Carrier_IATA"='ZZ' and "Bag_Adult_Male"=15 and "Bag_Adult_Female"=15 and "Bag_Adult_Child"=10) then raise exception 'FAIL preserved defaults'; end if;
if not exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" where "Carrier_IATA"='ZZ' and "Is_Baseline" and "Flight_Scope_Label"='All Flights' and "Class_Scope_Label"='All Classes' and "Per_Passenger_Method"='UNSET' and "Baggage_Weight_Per_Passenger" is null) then raise exception 'FAIL baseline'; end if;
end $$;
insert into "Basic_Carrier_Record"."Carrier_Flight_Variations" values('TST','Temporary B4 verification','ZZ');
update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Per_Passenger_Method"='STANDARD',"Baggage_Weight_Per_Passenger"=15 where "Carrier_IATA"='ZZ' and "Is_Baseline";
insert into "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"("Carrier_IATA","Class_Code","Flight_Type_Variation","Passenger_Category","Per_Piece_Method","Baggage_Weight_Per_Piece","Per_Passenger_Method","Baggage_Weight_Per_Passenger")
values ('ZZ','F','TST','CHILD','STANDARD',10,'STANDARD',12);
insert into "Basic_Carrier_Record"."Carrier_Planning_Assumptions"("Carrier_IATA","Class_Code","Flight_Type_Variation","Average_Bags_Per_Passenger","Average_Bag_Weight_Per_Passenger","Average_Bag_Volume") values('ZZ','F','TST',1.25,18.75,0.045);
insert into "Basic_Carrier_Record"."Carrier_Planning_Assumptions"("Carrier_IATA","Average_Bags_Per_Passenger","Average_Bag_Weight_Per_Passenger") values('ZZ',1.5,20);
do $$ begin
begin delete from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" where "Is_Baseline"; raise exception 'FAIL baseline delete'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Class_Code"='F' where "Is_Baseline"; raise exception 'FAIL baseline scope'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Baggage_Weight_Set_ID"=gen_random_uuid() where "Is_Baseline"; raise exception 'FAIL baseline ID'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Baggage_Weight_Per_Passenger"=null where "Is_Baseline"; raise exception 'FAIL standard missing weight'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Baggage_Weight_Per_Passenger"=-1 where "Is_Baseline"; raise exception 'FAIL negative passenger weight'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" set "Bag_Adult_Male"=-1 where "Carrier_IATA"='ZZ'; raise exception 'FAIL negative piece'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Class_Code"='Q' where not "Is_Baseline"; raise exception 'FAIL unknown class'; exception when foreign_key_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Planning_Assumptions" set "Class_Code"='Q'; raise exception 'FAIL planning class'; exception when foreign_key_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Planning_Assumptions" set "Flight_Type_Variation"='BAD'; raise exception 'FAIL planning variation'; exception when foreign_key_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Class_Codes" set "Carrier_Class_1_Code"='Q' where "Carrier_IATA"='ZZ'; raise exception 'FAIL referenced class'; exception when foreign_key_violation then null; end;
begin delete from "Basic_Carrier_Record"."Carrier_Flight_Variations" where "Carrier_IATA"='ZZ' and "Flight_Type_Variation"='TST'; raise exception 'FAIL referenced variation'; exception when foreign_key_violation then null; end;
begin insert into "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"("Carrier_IATA") values('ZZ'); raise exception 'FAIL duplicate baseline'; exception when unique_violation then null; end;
begin insert into "Basic_Carrier_Record"."Carrier_Planning_Assumptions"("Carrier_IATA","Average_Bags_Per_Passenger","Average_Bag_Weight_Per_Passenger") values('ZZ',1,15); raise exception 'FAIL duplicate planning default'; exception when unique_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Planning_Assumptions" set "Average_Bags_Per_Passenger"=-1; raise exception 'FAIL negative average'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Planning_Assumptions" set "Average_Bag_Volume"='NaN'::numeric; raise exception 'FAIL NaN volume'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Remarks"=repeat('x',2001); raise exception 'FAIL remarks limit'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Carrier_IATA"='XY'; raise exception 'FAIL carrier ownership'; exception when insufficient_privilege then null; end;
end $$;
update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Per_Passenger_Method"='ACTUAL' where "Is_Baseline";
update "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" set "Per_Piece_Method"='ACTUAL' where "Carrier_IATA"='ZZ';
do $$ begin
if not exists(select 1 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" where "Average_Bags_Per_Passenger"=1.25 and "Average_Bag_Volume"=0.045) then raise exception 'FAIL decimals'; end if;
if not exists(select 1 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" where "Class_Code" is null and "Average_Bag_Volume" is null) then raise exception 'FAIL unknown volume'; end if;
end $$;
reset role;
insert into application_security.organisations(organisation_id,organisation_name,organisation_type) values ('a5aa0000-0000-4000-8000-000000000001','Temporary carrier details verification','AIRLINE');
insert into application_security.organisation_users(organisation_id,user_id) values ('a5aa0000-0000-4000-8000-000000000001','b5c937a4-db85-4b47-bb59-23c99cc6799d');
insert into application_security.organisation_carrier_access(organisation_id,carrier_iata) values ('a5aa0000-0000-4000-8000-000000000001','ZZ');
insert into application_security.user_carrier_access(user_carrier_access_id,organisation_id,user_id,carrier_iata) values ('a5aa0000-0000-4000-8000-000000000002','a5aa0000-0000-4000-8000-000000000001','b5c937a4-db85-4b47-bb59-23c99cc6799d','ZZ');
insert into application_security.user_carrier_roles(user_carrier_access_id,role_id) select 'a5aa0000-0000-4000-8000-000000000002',role_id from application_security.roles where role_code='CONFIGURATION_EDITOR';
update application_security.user_global_roles set active=false where user_id='b5c937a4-db85-4b47-bb59-23c99cc6799d';
set local role authenticated;
do $$ declare n integer; begin
if (select count(*) from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS")<>2 then raise exception 'FAIL editor read'; end if;
update "Basic_Carrier_Record"."Carrier_Baggage_Weights_ALLFLIGHTS" set "Bag_Adult_Male"=1; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL editor defaults edit'; end if;
update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Baggage_Weight_Per_Passenger"=1; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL editor weights edit'; end if;
delete from "Basic_Carrier_Record"."Carrier_Planning_Assumptions"; get diagnostics n=row_count; if n<>0 then raise exception 'FAIL editor planning delete'; end if;
begin insert into "Basic_Carrier_Record"."Carrier_Planning_Assumptions"("Carrier_IATA","Class_Code","Average_Bags_Per_Passenger","Average_Bag_Weight_Per_Passenger") values('ZZ','C',1,15); raise exception 'FAIL editor insert'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update application_security.user_carrier_roles set role_id=(select role_id from application_security.roles where role_code='CARRIER_ADMINISTRATOR') where user_carrier_access_id='a5aa0000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ declare n integer; begin
update "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS" set "Per_Passenger_Method"='STANDARD',"Baggage_Weight_Per_Passenger"=16 where "Is_Baseline"; get diagnostics n=row_count; if n<>1 then raise exception 'FAIL CA baseline edit'; end if;
update "Basic_Carrier_Record"."Carrier_Planning_Assumptions" set "Average_Bags_Per_Passenger"=1.75; get diagnostics n=row_count; if n<>2 then raise exception 'FAIL CA planning edit'; end if;
begin insert into "Basic_Carrier_Record"."Carrier_Planning_Assumptions"("Carrier_IATA","Average_Bags_Per_Passenger","Average_Bag_Weight_Per_Passenger") values('XY',1,15); raise exception 'FAIL cross carrier'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
if exists(select 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS") or exists(select 1 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions") then raise exception 'FAIL unassigned read'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
begin perform 1 from "Basic_Carrier_Record"."Carrier_Baggage_Weights_BYCLASS"; raise exception 'FAIL anon'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS B4 baseline identity, defaults preserved, weights/methods, decimals, relationships, duplicates, SA/CA edits and editor/cross-carrier/anonymous denials' as result;
rollback;
