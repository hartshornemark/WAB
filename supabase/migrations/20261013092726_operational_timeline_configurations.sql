begin;

alter table "Basic_Carrier_Record"."Operational_Flights"
 add column "Delay_Minutes" integer not null default 0 check("Delay_Minutes" between 0 and 2880);

create table "Basic_Carrier_Record"."Operational_Timeline_Configurations"(
  "Carrier_IATA" varchar(2) not null references "Basic_Carrier_Record"."Basic_Carrier_Data"("Carrier_IATA") on update restrict on delete cascade,
  "Configuration_Scope" varchar(7) not null,
  "Aircraft_Type_IATA" varchar(3),
  "Booked_Passengers_Minutes" integer not null default 360,
  "Cargo_Offer_Minutes" integer not null default 360,
  "Cargo_Release_Minutes" integer not null default 120,
  "Load_Plan_Minutes" integer not null default 90,
  "Flight_Plan_Minutes" integer not null default 45,
  "Close_Out_Minutes" integer not null default 30,
  "Documents_Minutes" integer not null default 15,
  "Amber_Lead_Minutes" integer not null default 10,
  "Archive_After_STD_Minutes" integer not null default 1440,
  "Revision" integer not null default 1,
  "Updated_At" timestamptz not null default now(),
  "Updated_By" uuid not null default auth.uid(),
  primary key("Carrier_IATA","Configuration_Scope"),
  check(("Configuration_Scope"='DEFAULT' and "Aircraft_Type_IATA" is null) or ("Configuration_Scope"="Aircraft_Type_IATA" and "Aircraft_Type_IATA"~'^[A-Z0-9]{3}$')),
  check("Booked_Passengers_Minutes" between 0 and 1440),
  check("Cargo_Offer_Minutes" between 0 and 1440),
  check("Cargo_Release_Minutes" between 0 and 1440),
  check("Load_Plan_Minutes" between 0 and 1440),
  check("Flight_Plan_Minutes" between 0 and 1440),
  check("Close_Out_Minutes" between 0 and 1440),
  check("Documents_Minutes" between 0 and 1440),
  check("Amber_Lead_Minutes" between 1 and 120),
  check("Archive_After_STD_Minutes" between 60 and 10080),
  check("Booked_Passengers_Minutes">="Cargo_Offer_Minutes" and "Cargo_Offer_Minutes">="Cargo_Release_Minutes" and "Cargo_Release_Minutes">="Load_Plan_Minutes" and "Load_Plan_Minutes">="Flight_Plan_Minutes" and "Flight_Plan_Minutes">="Close_Out_Minutes" and "Close_Out_Minutes">="Documents_Minutes")
);

comment on table "Basic_Carrier_Record"."Operational_Timeline_Configurations" is 'Carrier default and aircraft-type variations for operational Load Control deadlines relative to STD.';

alter table "Basic_Carrier_Record"."Operational_Timeline_Configurations" enable row level security;
revoke all on table "Basic_Carrier_Record"."Operational_Timeline_Configurations" from public,anon,authenticated;
grant select,insert,update,delete on table "Basic_Carrier_Record"."Operational_Timeline_Configurations" to authenticated;

create policy operational_timeline_select on "Basic_Carrier_Record"."Operational_Timeline_Configurations"
 for select to authenticated using(
  (select private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW')) or
  (select private.has_global_permission('LOAD_CONTROL_VIEW')) or
  (select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or
  (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW'))
 );
create policy operational_timeline_insert on "Basic_Carrier_Record"."Operational_Timeline_Configurations"
 for insert to authenticated with check((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy operational_timeline_update on "Basic_Carrier_Record"."Operational_Timeline_Configurations"
 for update to authenticated
 using((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
 with check((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy operational_timeline_delete on "Basic_Carrier_Record"."Operational_Timeline_Configurations"
 for delete to authenticated using((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

create or replace function "Basic_Carrier_Record".operational_timeline_configuration_json(p_row "Basic_Carrier_Record"."Operational_Timeline_Configurations",p_source text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
  'aircraftType',p_row."Aircraft_Type_IATA",'revision',p_row."Revision",'source',p_source,
  'amberLeadMinutes',p_row."Amber_Lead_Minutes",'archiveAfterStdMinutes',p_row."Archive_After_STD_Minutes",
  'deadlines',jsonb_build_object(
   'BOOKED_PASSENGERS',p_row."Booked_Passengers_Minutes",'CARGO_OFFER',p_row."Cargo_Offer_Minutes",'CARGO_RELEASE',p_row."Cargo_Release_Minutes",
   'LOAD_PLAN',p_row."Load_Plan_Minutes",'FLIGHT_PLAN',p_row."Flight_Plan_Minutes",'CLOSE_OUT',p_row."Close_Out_Minutes",'DOCUMENTS',p_row."Documents_Minutes"
  )
 )
$$;

create or replace function "Basic_Carrier_Record".system_operational_timeline_configuration()
returns jsonb language sql immutable security invoker set search_path='' as $$
 select jsonb_build_object(
  'aircraftType',null,'revision',0,'source','SYSTEM_DEFAULT','amberLeadMinutes',10,'archiveAfterStdMinutes',1440,
  'deadlines',jsonb_build_object('BOOKED_PASSENGERS',360,'CARGO_OFFER',360,'CARGO_RELEASE',120,'LOAD_PLAN',90,'FLIGHT_PLAN',45,'CLOSE_OUT',30,'DOCUMENTS',15)
 )
$$;

create or replace function "Basic_Carrier_Record".get_operational_timeline_configurations(p_iata text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare can_view boolean;can_edit boolean;default_row "Basic_Carrier_Record"."Operational_Timeline_Configurations";default_json jsonb;overrides jsonb;types jsonb;
begin
 can_view:=(select auth.uid()) is not null and (
  private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW') or
  private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')
 );
 can_edit:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select * into default_row from "Basic_Carrier_Record"."Operational_Timeline_Configurations" where "Carrier_IATA"=p_iata and "Configuration_Scope"='DEFAULT';
 default_json:=case when default_row."Carrier_IATA" is null then "Basic_Carrier_Record".system_operational_timeline_configuration() else "Basic_Carrier_Record".operational_timeline_configuration_json(default_row,'CARRIER_DEFAULT') end;
 select coalesce(jsonb_agg("Basic_Carrier_Record".operational_timeline_configuration_json(c,'AIRCRAFT_TYPE') order by c."Aircraft_Type_IATA"),'[]'::jsonb) into overrides
  from "Basic_Carrier_Record"."Operational_Timeline_Configurations" c where c."Carrier_IATA"=p_iata and c."Configuration_Scope"<>'DEFAULT';
 select coalesce(jsonb_agg(t.code order by t.code),'[]'::jsonb) into types from(
  select distinct upper(btrim("Aircraft_Type_IATA")) code from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata
 )t;
 return jsonb_build_object('canEdit',can_edit,'aircraftTypes',types,'defaultConfiguration',default_json,'overrides',overrides);
end $$;

create or replace function "Basic_Carrier_Record".resolve_operational_timeline_configuration(p_iata text,p_aircraft_type text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare snapshot jsonb;aircraft_type text:=upper(btrim(coalesce(p_aircraft_type,'')));resolved jsonb;
begin
 snapshot:="Basic_Carrier_Record".get_operational_timeline_configurations(p_iata);
 select value into resolved from jsonb_array_elements(snapshot->'overrides') where value->>'aircraftType'=aircraft_type limit 1;
 return coalesce(resolved,snapshot->'defaultConfiguration');
end $$;

create or replace function "Basic_Carrier_Record".save_operational_timeline_configuration(p_iata text,p_aircraft_type text,p_expected_revision integer,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare aircraft_type text:=nullif(upper(btrim(coalesce(p_aircraft_type,''))),'');scope text:=coalesce(aircraft_type,'DEFAULT');current_revision integer;booked integer;offer integer;release integer;load_plan integer;flight_plan integer;close_out integer;documents integer;amber integer;archive_after integer;
begin
 if not(private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if aircraft_type is not null and (aircraft_type!~'^[A-Z0-9]{3}$' or not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and upper(btrim("Aircraft_Type_IATA"))=aircraft_type)) then raise exception 'Select a carrier aircraft type' using errcode='23503';end if;
 booked:=(p_values->'deadlines'->>'BOOKED_PASSENGERS')::integer;offer:=(p_values->'deadlines'->>'CARGO_OFFER')::integer;release:=(p_values->'deadlines'->>'CARGO_RELEASE')::integer;load_plan:=(p_values->'deadlines'->>'LOAD_PLAN')::integer;flight_plan:=(p_values->'deadlines'->>'FLIGHT_PLAN')::integer;close_out:=(p_values->'deadlines'->>'CLOSE_OUT')::integer;documents:=(p_values->'deadlines'->>'DOCUMENTS')::integer;amber:=(p_values->>'amberLeadMinutes')::integer;archive_after:=(p_values->>'archiveAfterStdMinutes')::integer;
 if booked not between 0 and 1440 or offer not between 0 and 1440 or release not between 0 and 1440 or load_plan not between 0 and 1440 or flight_plan not between 0 and 1440 or close_out not between 0 and 1440 or documents not between 0 and 1440 or amber not between 1 and 120 or archive_after not between 60 and 10080 or not(booked>=offer and offer>=release and release>=load_plan and load_plan>=flight_plan and flight_plan>=close_out and close_out>=documents) then raise exception 'Check the operational timeline deadlines' using errcode='23514';end if;
 select "Revision" into current_revision from "Basic_Carrier_Record"."Operational_Timeline_Configurations" where "Carrier_IATA"=p_iata and "Configuration_Scope"=scope for update;
 if coalesce(current_revision,0)<>p_expected_revision then raise exception 'The operational timeline changed while you were editing' using errcode='PT409';end if;
 insert into "Basic_Carrier_Record"."Operational_Timeline_Configurations"("Carrier_IATA","Configuration_Scope","Aircraft_Type_IATA","Booked_Passengers_Minutes","Cargo_Offer_Minutes","Cargo_Release_Minutes","Load_Plan_Minutes","Flight_Plan_Minutes","Close_Out_Minutes","Documents_Minutes","Amber_Lead_Minutes","Archive_After_STD_Minutes","Revision","Updated_At","Updated_By")
 values(p_iata,scope,aircraft_type,booked,offer,release,load_plan,flight_plan,close_out,documents,amber,archive_after,1,now(),auth.uid())
 on conflict("Carrier_IATA","Configuration_Scope") do update set "Booked_Passengers_Minutes"=excluded."Booked_Passengers_Minutes","Cargo_Offer_Minutes"=excluded."Cargo_Offer_Minutes","Cargo_Release_Minutes"=excluded."Cargo_Release_Minutes","Load_Plan_Minutes"=excluded."Load_Plan_Minutes","Flight_Plan_Minutes"=excluded."Flight_Plan_Minutes","Close_Out_Minutes"=excluded."Close_Out_Minutes","Documents_Minutes"=excluded."Documents_Minutes","Amber_Lead_Minutes"=excluded."Amber_Lead_Minutes","Archive_After_STD_Minutes"=excluded."Archive_After_STD_Minutes","Revision"="Basic_Carrier_Record"."Operational_Timeline_Configurations"."Revision"+1,"Updated_At"=now(),"Updated_By"=auth.uid();
 return "Basic_Carrier_Record".get_operational_timeline_configurations(p_iata);
end $$;

create or replace function "Basic_Carrier_Record".delete_operational_timeline_configuration(p_iata text,p_aircraft_type text,p_expected_revision integer)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare aircraft_type text:=upper(btrim(coalesce(p_aircraft_type,'')));deleted integer;
begin
 if not(private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if aircraft_type='' then raise exception 'The carrier default cannot be removed' using errcode='23514';end if;
 delete from "Basic_Carrier_Record"."Operational_Timeline_Configurations" where "Carrier_IATA"=p_iata and "Configuration_Scope"=aircraft_type and "Revision"=p_expected_revision;
 get diagnostics deleted=row_count;if deleted<>1 then raise exception 'The operational timeline changed while you were editing' using errcode='PT409';end if;
 return "Basic_Carrier_Record".get_operational_timeline_configurations(p_iata);
end $$;

create or replace function "Basic_Carrier_Record".get_operational_flight_delay(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare f record;
begin
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')) then raise exception 'Not authorised' using errcode='42501';end if;
 select "Delay_Minutes","Version" into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
 return jsonb_build_object('delayMinutes',f."Delay_Minutes",'version',f."Version");
end $$;

create or replace function "Basic_Carrier_Record".save_operational_flight_delay(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_delay_minutes integer)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare f record;
begin
 if not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_EDIT') or private.has_global_permission('LOAD_CONTROL_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 if p_delay_minutes is null or p_delay_minutes not between 0 and 2880 then raise exception 'Delay must be between 0 and 2880 minutes' using errcode='23514';end if;
 select * into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
 if f."Version"<>p_expected_version then raise exception 'The operational flight changed while you were editing' using errcode='PT409';end if;
 update "Basic_Carrier_Record"."Operational_Flights" set "Delay_Minutes"=p_delay_minutes,"Version"="Version"+1,"Updated_At"=now() where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 insert into "Basic_Carrier_Record"."Operational_Flight_Events"("Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data","Actor_User_ID") values(p_operational_flight_id,p_iata,'DELAY_UPDATED',f."Status",f."Status",jsonb_build_object('previousDelayMinutes',f."Delay_Minutes",'delayMinutes',p_delay_minutes),auth.uid());
 return "Basic_Carrier_Record".get_operational_flight_delay(p_iata,p_operational_flight_id);
end $$;

revoke all on function "Basic_Carrier_Record".operational_timeline_configuration_json("Basic_Carrier_Record"."Operational_Timeline_Configurations",text) from public,anon;
revoke all on function "Basic_Carrier_Record".system_operational_timeline_configuration() from public,anon;
revoke all on function "Basic_Carrier_Record".get_operational_timeline_configurations(text) from public,anon;
revoke all on function "Basic_Carrier_Record".resolve_operational_timeline_configuration(text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_operational_timeline_configuration(text,text,integer,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".delete_operational_timeline_configuration(text,text,integer) from public,anon;
revoke all on function "Basic_Carrier_Record".get_operational_flight_delay(text,uuid) from public,anon;
revoke all on function "Basic_Carrier_Record".save_operational_flight_delay(text,uuid,integer,integer) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_timeline_configurations(text) to authenticated;
grant execute on function "Basic_Carrier_Record".resolve_operational_timeline_configuration(text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".operational_timeline_configuration_json("Basic_Carrier_Record"."Operational_Timeline_Configurations",text) to authenticated;
grant execute on function "Basic_Carrier_Record".system_operational_timeline_configuration() to authenticated;
grant execute on function "Basic_Carrier_Record".save_operational_timeline_configuration(text,text,integer,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".delete_operational_timeline_configuration(text,text,integer) to authenticated;
grant execute on function "Basic_Carrier_Record".get_operational_flight_delay(text,uuid) to authenticated;
grant execute on function "Basic_Carrier_Record".save_operational_flight_delay(text,uuid,integer,integer) to authenticated;

notify pgrst,'reload schema';
commit;
