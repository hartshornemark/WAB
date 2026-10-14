begin;

create table "Basic_Carrier_Record"."Operational_Fuel_Plans"(
  "Operational_Flight_ID" uuid primary key references "Basic_Carrier_Record"."Operational_Flights"("Operational_Flight_ID") on update cascade on delete cascade,
  "Carrier_IATA" varchar(2) not null,
  "Status" text not null default 'PRELIMINARY' check("Status" in('PRELIMINARY','FINAL')),
  "Fuel_Configuration_Code" varchar(12),
  "Fuel_Specific_Gravity" numeric(6,4) not null check("Fuel_Specific_Gravity">0 and "Fuel_Specific_Gravity"<=2),
  "Block_Fuel" integer not null check("Block_Fuel">=0),
  "Taxi_Fuel" integer not null check("Taxi_Fuel">=0),
  "Trip_Fuel" integer not null check("Trip_Fuel">=0),
  "Take_Off_Fuel" integer generated always as ("Block_Fuel"-"Taxi_Fuel") stored,
  "Landing_Fuel" integer generated always as ("Block_Fuel"-"Taxi_Fuel"-"Trip_Fuel") stored,
  "Version" integer not null default 1 check("Version">0),
  "Updated_By" uuid not null default auth.uid(),
  "Updated_At" timestamptz not null default now(),
  constraint "operational_fuel_quantities" check("Taxi_Fuel"<="Block_Fuel" and "Trip_Fuel"<=("Block_Fuel"-"Taxi_Fuel"))
);

create index "operational_fuel_plan_carrier_idx" on "Basic_Carrier_Record"."Operational_Fuel_Plans"("Carrier_IATA","Operational_Flight_ID");
alter table "Basic_Carrier_Record"."Operational_Fuel_Plans" enable row level security;
grant select on "Basic_Carrier_Record"."Operational_Fuel_Plans" to authenticated;
create policy "operational_fuel_plans_select" on "Basic_Carrier_Record"."Operational_Fuel_Plans" for select to authenticated using(
  (select private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW')) or
  (select private.has_global_permission('LOAD_CONTROL_VIEW'))
);

create or replace function "Basic_Carrier_Record".get_operational_fuel_plan(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare p "Basic_Carrier_Record"."Operational_Fuel_Plans"%rowtype;
begin
 p_iata:=upper(btrim(p_iata));
 if not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW')or private.has_global_permission('LOAD_CONTROL_VIEW'))then raise exception 'Permission denied' using errcode='42501';end if;
 select*into p from "Basic_Carrier_Record"."Operational_Fuel_Plans" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 return jsonb_build_object(
  'version',coalesce(p."Version",0),'status',case when p."Operational_Flight_ID" is null then'EMPTY'else p."Status" end,
  'configurationCode',p."Fuel_Configuration_Code",'specificGravity',p."Fuel_Specific_Gravity",
  'blockFuel',p."Block_Fuel",'taxiFuel',p."Taxi_Fuel",'tripFuel',p."Trip_Fuel",'takeOffFuel',p."Take_Off_Fuel",'landingFuel',p."Landing_Fuel",'updatedAt',p."Updated_At"
 );
end$$;

create or replace function "Basic_Carrier_Record".save_operational_fuel_plan(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
  current_version integer;current_edition integer;configuration_code text;specific_gravity numeric;block_fuel integer;taxi_fuel integer;trip_fuel integer;maximum_curve_weight integer;fuel_status text;
begin
 p_iata:=upper(btrim(p_iata));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then raise exception 'Permission denied' using errcode='42501';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object'then raise exception 'Fuel plan is incomplete' using errcode='22023';end if;
 select*into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if not found then raise exception 'Operational flight not found' using errcode='22023';end if;
 select coalesce("Version",0)into current_version from "Basic_Carrier_Record"."Operational_Fuel_Plans" where "Operational_Flight_ID"=p_operational_flight_id;
 current_version:=coalesce(current_version,0);
 if current_version<>p_expected_version then raise exception 'The fuel plan has been revised in another session. Reload before saving.' using errcode='40001';end if;
 select coalesce(max("Edition_Number"),0)into current_edition from "Basic_Carrier_Record"."Operational_Load_Plan_Editions" where "Operational_Flight_ID"=p_operational_flight_id;
 if current_edition<1 then raise exception 'Create a load plan before recording operational fuel.' using errcode='22023';end if;
 configuration_code:=nullif(upper(btrim(p_values->>'configurationCode')),'');specific_gravity:=(p_values->>'specificGravity')::numeric;block_fuel:=(p_values->>'blockFuel')::integer;taxi_fuel:=(p_values->>'taxiFuel')::integer;trip_fuel:=(p_values->>'tripFuel')::integer;fuel_status:=case when coalesce((p_values->>'finalise')::boolean,false)then'FINAL'else'PRELIMINARY'end;
 if specific_gravity<=0 or specific_gravity>2 or block_fuel<0 or taxi_fuel<0 or trip_fuel<0 or taxi_fuel>block_fuel or trip_fuel>block_fuel-taxi_fuel then raise exception 'Check block, taxi and trip fuel.' using errcode='23514';end if;
 select max("Fuel_Weight")into maximum_curve_weight from "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=f."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and "Fuel_Specific_Gravity"=specific_gravity and "Fuel_Configuration_Code" is not distinct from configuration_code;
 if maximum_curve_weight is null then raise exception 'The selected standard fuel curve is not configured for this aircraft.' using errcode='22023';end if;
 if block_fuel>maximum_curve_weight then raise exception 'Block fuel exceeds the selected fuel curve.' using errcode='23514';end if;
 insert into "Basic_Carrier_Record"."Operational_Fuel_Plans"("Operational_Flight_ID","Carrier_IATA","Status","Fuel_Configuration_Code","Fuel_Specific_Gravity","Block_Fuel","Taxi_Fuel","Trip_Fuel","Updated_By")
 values(p_operational_flight_id,p_iata,fuel_status,configuration_code,specific_gravity,block_fuel,taxi_fuel,trip_fuel,auth.uid())
 on conflict("Operational_Flight_ID")do update set "Status"=excluded."Status","Fuel_Configuration_Code"=excluded."Fuel_Configuration_Code","Fuel_Specific_Gravity"=excluded."Fuel_Specific_Gravity","Block_Fuel"=excluded."Block_Fuel","Taxi_Fuel"=excluded."Taxi_Fuel","Trip_Fuel"=excluded."Trip_Fuel","Version"="Basic_Carrier_Record"."Operational_Fuel_Plans"."Version"+1,"Updated_By"=auth.uid(),"Updated_At"=now();
 insert into "Basic_Carrier_Record"."Operational_Flight_Events"("Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data","Actor_User_ID")values(p_operational_flight_id,p_iata,'UPDATED',f."Status",f."Status",jsonb_build_object('action',case when fuel_status='FINAL'then'FUEL_DATA_FINALISED'else'FUEL_PLAN_SAVED'end,'fuelStatus',fuel_status,'blockFuel',block_fuel,'takeOffFuel',block_fuel-taxi_fuel,'landingFuel',block_fuel-taxi_fuel-trip_fuel),auth.uid());
 return "Basic_Carrier_Record".get_operational_fuel_plan(p_iata,p_operational_flight_id);
end$$;

revoke all on function "Basic_Carrier_Record".get_operational_fuel_plan(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_fuel_plan(text,uuid) to authenticated;
revoke all on function "Basic_Carrier_Record".save_operational_fuel_plan(text,uuid,integer,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_fuel_plan(text,uuid,integer,jsonb) to authenticated;
comment on table "Basic_Carrier_Record"."Operational_Fuel_Plans" is 'Operational block, taxi and trip fuel. Balance effects are recalculated against the current load plan; fuel is explicitly preliminary or final.';
notify pgrst,'reload schema';
commit;
