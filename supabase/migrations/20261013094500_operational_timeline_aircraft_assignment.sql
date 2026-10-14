begin;

alter table "Basic_Carrier_Record"."Operational_Timeline_Configurations"
 add column "Aircraft_Assignment_Minutes" integer not null default 90
 check("Aircraft_Assignment_Minutes" between 0 and 1440);

alter table "Basic_Carrier_Record"."Operational_Timeline_Configurations"
 drop constraint "Operational_Timeline_Configurations_check1",
 add constraint operational_timeline_deadline_order check(
  "Booked_Passengers_Minutes">="Cargo_Offer_Minutes" and
  "Cargo_Offer_Minutes">="Cargo_Release_Minutes" and
  "Cargo_Release_Minutes">="Aircraft_Assignment_Minutes" and
  "Aircraft_Assignment_Minutes">="Load_Plan_Minutes" and
  "Load_Plan_Minutes">="Flight_Plan_Minutes" and
  "Flight_Plan_Minutes">="Close_Out_Minutes" and
  "Close_Out_Minutes">="Documents_Minutes"
 );

create or replace function "Basic_Carrier_Record".operational_timeline_configuration_json(p_row "Basic_Carrier_Record"."Operational_Timeline_Configurations",p_source text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
  'aircraftType',p_row."Aircraft_Type_IATA",'revision',p_row."Revision",'source',p_source,
  'amberLeadMinutes',p_row."Amber_Lead_Minutes",'archiveAfterStdMinutes',p_row."Archive_After_STD_Minutes",
  'deadlines',jsonb_build_object(
   'BOOKED_PASSENGERS',p_row."Booked_Passengers_Minutes",'CARGO_OFFER',p_row."Cargo_Offer_Minutes",'CARGO_RELEASE',p_row."Cargo_Release_Minutes",
   'AIRCRAFT_ASSIGNMENT',p_row."Aircraft_Assignment_Minutes",'LOAD_PLAN',p_row."Load_Plan_Minutes",'FLIGHT_PLAN',p_row."Flight_Plan_Minutes",
   'CLOSE_OUT',p_row."Close_Out_Minutes",'DOCUMENTS',p_row."Documents_Minutes"
  )
 )
$$;

create or replace function "Basic_Carrier_Record".system_operational_timeline_configuration()
returns jsonb language sql immutable security invoker set search_path='' as $$
 select jsonb_build_object(
  'aircraftType',null,'revision',0,'source','SYSTEM_DEFAULT','amberLeadMinutes',10,'archiveAfterStdMinutes',1440,
  'deadlines',jsonb_build_object('BOOKED_PASSENGERS',360,'CARGO_OFFER',360,'CARGO_RELEASE',120,'AIRCRAFT_ASSIGNMENT',90,'LOAD_PLAN',90,'FLIGHT_PLAN',45,'CLOSE_OUT',30,'DOCUMENTS',15)
 )
$$;

create or replace function "Basic_Carrier_Record".save_operational_timeline_configuration(p_iata text,p_aircraft_type text,p_expected_revision integer,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare aircraft_type text:=nullif(upper(btrim(coalesce(p_aircraft_type,''))),'');scope text:=coalesce(aircraft_type,'DEFAULT');current_revision integer;booked integer;offer integer;release integer;assignment integer;load_plan integer;flight_plan integer;close_out integer;documents integer;amber integer;archive_after integer;
begin
 if not(private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if aircraft_type is not null and (aircraft_type!~'^[A-Z0-9]{3}$' or not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and upper(btrim("Aircraft_Type_IATA"))=aircraft_type)) then raise exception 'Select a carrier aircraft type' using errcode='23503';end if;
 booked:=(p_values->'deadlines'->>'BOOKED_PASSENGERS')::integer;offer:=(p_values->'deadlines'->>'CARGO_OFFER')::integer;release:=(p_values->'deadlines'->>'CARGO_RELEASE')::integer;assignment:=(p_values->'deadlines'->>'AIRCRAFT_ASSIGNMENT')::integer;load_plan:=(p_values->'deadlines'->>'LOAD_PLAN')::integer;flight_plan:=(p_values->'deadlines'->>'FLIGHT_PLAN')::integer;close_out:=(p_values->'deadlines'->>'CLOSE_OUT')::integer;documents:=(p_values->'deadlines'->>'DOCUMENTS')::integer;amber:=(p_values->>'amberLeadMinutes')::integer;archive_after:=(p_values->>'archiveAfterStdMinutes')::integer;
 if booked not between 0 and 1440 or offer not between 0 and 1440 or release not between 0 and 1440 or assignment not between 0 and 1440 or load_plan not between 0 and 1440 or flight_plan not between 0 and 1440 or close_out not between 0 and 1440 or documents not between 0 and 1440 or amber not between 1 and 120 or archive_after not between 60 and 10080 or not(booked>=offer and offer>=release and release>=assignment and assignment>=load_plan and load_plan>=flight_plan and flight_plan>=close_out and close_out>=documents) then raise exception 'Check the operational timeline deadlines' using errcode='23514';end if;
 select "Revision" into current_revision from "Basic_Carrier_Record"."Operational_Timeline_Configurations" where "Carrier_IATA"=p_iata and "Configuration_Scope"=scope for update;
 if coalesce(current_revision,0)<>p_expected_revision then raise exception 'The operational timeline changed while you were editing' using errcode='PT409';end if;
 insert into "Basic_Carrier_Record"."Operational_Timeline_Configurations"("Carrier_IATA","Configuration_Scope","Aircraft_Type_IATA","Booked_Passengers_Minutes","Cargo_Offer_Minutes","Cargo_Release_Minutes","Aircraft_Assignment_Minutes","Load_Plan_Minutes","Flight_Plan_Minutes","Close_Out_Minutes","Documents_Minutes","Amber_Lead_Minutes","Archive_After_STD_Minutes","Revision","Updated_At","Updated_By")
 values(p_iata,scope,aircraft_type,booked,offer,release,assignment,load_plan,flight_plan,close_out,documents,amber,archive_after,1,now(),auth.uid())
 on conflict("Carrier_IATA","Configuration_Scope") do update set "Booked_Passengers_Minutes"=excluded."Booked_Passengers_Minutes","Cargo_Offer_Minutes"=excluded."Cargo_Offer_Minutes","Cargo_Release_Minutes"=excluded."Cargo_Release_Minutes","Aircraft_Assignment_Minutes"=excluded."Aircraft_Assignment_Minutes","Load_Plan_Minutes"=excluded."Load_Plan_Minutes","Flight_Plan_Minutes"=excluded."Flight_Plan_Minutes","Close_Out_Minutes"=excluded."Close_Out_Minutes","Documents_Minutes"=excluded."Documents_Minutes","Amber_Lead_Minutes"=excluded."Amber_Lead_Minutes","Archive_After_STD_Minutes"=excluded."Archive_After_STD_Minutes","Revision"="Basic_Carrier_Record"."Operational_Timeline_Configurations"."Revision"+1,"Updated_At"=now(),"Updated_By"=auth.uid();
 return "Basic_Carrier_Record".get_operational_timeline_configurations(p_iata);
end $$;

notify pgrst,'reload schema';
commit;
