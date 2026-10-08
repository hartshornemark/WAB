begin;

create table "Basic_Carrier_Record"."Operational_Load_Plan_Editions"(
  "Load_Plan_Edition_ID" uuid primary key default gen_random_uuid(),
  "Operational_Flight_ID" uuid not null references "Basic_Carrier_Record"."Operational_Flights"("Operational_Flight_ID") on update cascade on delete cascade,
  "Carrier_IATA" varchar(2) not null,
  "Edition_Number" integer not null check("Edition_Number">0),
  "Revision_Source" text not null check("Revision_Source" in('AUTOLOAD','MANUAL','RESET')),
  "Assignments" jsonb not null check(jsonb_typeof("Assignments")='array'),
  "Solver_Engine" text not null,
  "Solver_Status" text not null,
  "Solve_Milliseconds" integer not null check("Solve_Milliseconds">=0),
  "Unload_Inversions" integer,
  "Ideal_Trim_Deviation_Scaled" bigint,
  "Created_By" uuid not null default auth.uid(),
  "Created_At" timestamptz not null default now(),
  unique("Operational_Flight_ID","Edition_Number")
);
create index "operational_load_plan_carrier_flight_edition_idx" on "Basic_Carrier_Record"."Operational_Load_Plan_Editions"("Carrier_IATA","Operational_Flight_ID","Edition_Number" desc);
alter table "Basic_Carrier_Record"."Operational_Load_Plan_Editions" enable row level security;
grant select on "Basic_Carrier_Record"."Operational_Load_Plan_Editions" to authenticated;
create policy "operational_load_plan_editions_select" on "Basic_Carrier_Record"."Operational_Load_Plan_Editions" for select to authenticated using((select private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW'))or(select private.has_global_permission('LOAD_CONTROL_VIEW')));

create or replace function "Basic_Carrier_Record".get_operational_load_plan(p_iata text,p_operational_flight_id uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare p "Basic_Carrier_Record"."Operational_Load_Plan_Editions"%rowtype;
begin
 if not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW')or private.has_global_permission('LOAD_CONTROL_VIEW'))then raise exception 'Permission denied' using errcode='42501';end if;
 select*into p from "Basic_Carrier_Record"."Operational_Load_Plan_Editions" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id order by "Edition_Number" desc limit 1;
 return jsonb_build_object('edition',coalesce(p."Edition_Number",0),'source',p."Revision_Source",'assignments',coalesce(p."Assignments",'[]'::jsonb),'createdAt',p."Created_At");
end$$;

create or replace function "Basic_Carrier_Record".save_operational_load_plan(p_iata text,p_operational_flight_id uuid,p_expected_edition integer,p_source text,p_solution jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare current_edition integer;next_edition integer;source_value text:=upper(btrim(p_source));assignments jsonb:=p_solution->'assignments';f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
begin
 p_iata:=upper(btrim(p_iata));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then raise exception 'Permission denied' using errcode='42501';end if;
 select*into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if not found then raise exception 'Operational flight not found' using errcode='22023';end if;
 select coalesce(max("Edition_Number"),0) into current_edition from "Basic_Carrier_Record"."Operational_Load_Plan_Editions" where "Operational_Flight_ID"=p_operational_flight_id;
 if current_edition<>p_expected_edition then raise exception 'The load plan has been revised in another session. Reload before saving another edition.' using errcode='40001';end if;
 if source_value not in('AUTOLOAD','MANUAL','RESET')then raise exception 'Invalid load plan revision source' using errcode='22023';end if;
 if assignments is null or jsonb_typeof(assignments)<>'array'or jsonb_array_length(assignments)=0 then raise exception 'A load plan must contain assignments' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(assignments)a where jsonb_typeof(a)<>'object'or coalesce(a->>'loadId','')=''or coalesce(a->>'positionId','')='')then raise exception 'The load plan assignments are incomplete' using errcode='22023';end if;
 next_edition:=current_edition+1;
 insert into "Basic_Carrier_Record"."Operational_Load_Plan_Editions"("Operational_Flight_ID","Carrier_IATA","Edition_Number","Revision_Source","Assignments","Solver_Engine","Solver_Status","Solve_Milliseconds","Unload_Inversions","Ideal_Trim_Deviation_Scaled") values(p_operational_flight_id,p_iata,next_edition,source_value,assignments,coalesce(p_solution->>'engine','UNKNOWN'),coalesce(p_solution->>'status','FEASIBLE'),coalesce((p_solution->>'solveMilliseconds')::integer,0),nullif(p_solution->>'sequencePenalty','')::integer,nullif(p_solution->>'trimDeviationScaled','')::bigint);
 insert into "Basic_Carrier_Record"."Operational_Flight_Events"("Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data") values(p_operational_flight_id,p_iata,'UPDATED',f."Status",f."Status",jsonb_build_object('loadPlanEdition',next_edition,'revisionSource',source_value));
 return jsonb_build_object('edition',next_edition,'source',source_value,'assignments',assignments,'createdAt',now());
end$$;
revoke all on function "Basic_Carrier_Record".get_operational_load_plan(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_load_plan(text,uuid) to authenticated;
revoke all on function "Basic_Carrier_Record".save_operational_load_plan(text,uuid,integer,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_load_plan(text,uuid,integer,text,jsonb) to authenticated;
notify pgrst,'reload schema';
comment on table "Basic_Carrier_Record"."Operational_Load_Plan_Editions" is 'Immutable editions of each operational loading instruction. Every AUTOLOAD generation and validated manual revision creates the next edition.';
commit;
