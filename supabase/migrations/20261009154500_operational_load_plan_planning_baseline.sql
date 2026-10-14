begin;

alter table "Basic_Carrier_Record"."Operational_Load_Plan_Editions"
  add column "Estimated_ZFW" numeric,
  add column "Planned_LIZFW" numeric;

comment on column "Basic_Carrier_Record"."Operational_Load_Plan_Editions"."Estimated_ZFW" is
  'Estimated zero fuel weight captured when the first load-plan edition is committed. Null on legacy and later editions.';
comment on column "Basic_Carrier_Record"."Operational_Load_Plan_Editions"."Planned_LIZFW" is
  'Planned laden index at estimated ZFW captured when the first load-plan edition is committed. Null on legacy and later editions.';

create or replace function "Basic_Carrier_Record".get_operational_load_plan(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  p "Basic_Carrier_Record"."Operational_Load_Plan_Editions"%rowtype;
  baseline jsonb;
begin
  p_iata:=upper(btrim(p_iata));
  if not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW')or private.has_global_permission('LOAD_CONTROL_VIEW'))then
    raise exception 'Permission denied' using errcode='42501';
  end if;
  select*into p from "Basic_Carrier_Record"."Operational_Load_Plan_Editions"
    where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id
    order by "Edition_Number" desc limit 1;
  select jsonb_build_object(
    'edition',1,
    'estimatedZfw',"Estimated_ZFW",
    'plannedLizfw',"Planned_LIZFW",
    'createdAt',"Created_At"
  ) into baseline
  from "Basic_Carrier_Record"."Operational_Load_Plan_Editions"
  where "Carrier_IATA"=p_iata
    and "Operational_Flight_ID"=p_operational_flight_id
    and "Edition_Number"=1
    and "Estimated_ZFW" is not null
    and "Planned_LIZFW" is not null;
  return jsonb_build_object(
    'edition',coalesce(p."Edition_Number",0),
    'source',p."Revision_Source",
    'assignments',coalesce(p."Assignments",'[]'::jsonb),
    'solution',case when p."Edition_Number" is null then null else jsonb_build_object(
      'status',p."Solver_Status",
      'engine',p."Solver_Engine",
      'solveMilliseconds',p."Solve_Milliseconds",
      'assignments',p."Assignments",
      'sequencePenalty',p."Unload_Inversions",
      'usedSimplicityGroups',null,
      'trimDeviationScaled',p."Ideal_Trim_Deviation_Scaled",
      'messages','[]'::jsonb
    )end,
    'createdAt',p."Created_At",
    'planningBaseline',baseline
  );
end$$;

drop function "Basic_Carrier_Record".save_operational_load_plan(text,uuid,integer,text,jsonb);

create function "Basic_Carrier_Record".save_operational_load_plan(
  p_iata text,
  p_operational_flight_id uuid,
  p_expected_edition integer,
  p_source text,
  p_solution jsonb,
  p_estimated_zfw numeric,
  p_planned_lizfw numeric
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  current_edition integer;
  next_edition integer;
  source_value text:=upper(btrim(p_source));
  assignments jsonb:=p_solution->'assignments';
  f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
  baseline jsonb;
begin
  p_iata:=upper(btrim(p_iata));
  if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then
    raise exception 'Permission denied' using errcode='42501';
  end if;
  select*into f from "Basic_Carrier_Record"."Operational_Flights"
    where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
  if not found then raise exception 'Operational flight not found' using errcode='22023';end if;
  select coalesce(max("Edition_Number"),0) into current_edition
    from "Basic_Carrier_Record"."Operational_Load_Plan_Editions"
    where "Operational_Flight_ID"=p_operational_flight_id;
  if current_edition<>p_expected_edition then
    raise exception 'The load plan has been revised in another session. Reload before saving another edition.' using errcode='PT409';
  end if;
  if source_value not in('AUTOLOAD','MANUAL','RESET')then raise exception 'Invalid load plan revision source' using errcode='22023';end if;
  if assignments is null or jsonb_typeof(assignments)<>'array'or jsonb_array_length(assignments)=0 then raise exception 'A load plan must contain assignments' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements(assignments)a where jsonb_typeof(a)<>'object'or coalesce(a->>'loadId','')=''or coalesce(a->>'positionId','')='')then raise exception 'The load plan assignments are incomplete' using errcode='22023';end if;
  next_edition:=current_edition+1;
  if next_edition=1 and(
    p_estimated_zfw is null or p_estimated_zfw<=0 or p_estimated_zfw>1000000000
    or p_planned_lizfw is null or p_planned_lizfw<'-1000000'::numeric or p_planned_lizfw>'1000000'::numeric
  )then
    raise exception 'The first load-plan edition requires a valid estimated ZFW and planned LIZFW.' using errcode='22023';
  end if;
  insert into "Basic_Carrier_Record"."Operational_Load_Plan_Editions"(
    "Operational_Flight_ID","Carrier_IATA","Edition_Number","Revision_Source","Assignments",
    "Solver_Engine","Solver_Status","Solve_Milliseconds","Unload_Inversions","Ideal_Trim_Deviation_Scaled",
    "Estimated_ZFW","Planned_LIZFW"
  ) values(
    p_operational_flight_id,p_iata,next_edition,source_value,assignments,
    coalesce(p_solution->>'engine','UNKNOWN'),coalesce(p_solution->>'status','FEASIBLE'),
    coalesce((p_solution->>'solveMilliseconds')::integer,0),nullif(p_solution->>'sequencePenalty','')::integer,
    nullif(p_solution->>'trimDeviationScaled','')::bigint,
    case when next_edition=1 then p_estimated_zfw end,
    case when next_edition=1 then p_planned_lizfw end
  );
  select jsonb_build_object(
    'edition',1,
    'estimatedZfw',"Estimated_ZFW",
    'plannedLizfw',"Planned_LIZFW",
    'createdAt',"Created_At"
  ) into baseline
  from "Basic_Carrier_Record"."Operational_Load_Plan_Editions"
  where "Operational_Flight_ID"=p_operational_flight_id and "Edition_Number"=1
    and "Estimated_ZFW" is not null and "Planned_LIZFW" is not null;
  insert into "Basic_Carrier_Record"."Operational_Flight_Events"(
    "Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data"
  ) values(
    p_operational_flight_id,p_iata,'UPDATED',f."Status",f."Status",
    jsonb_strip_nulls(jsonb_build_object(
      'loadPlanEdition',next_edition,
      'revisionSource',source_value,
      'planningBaseline',case when next_edition=1 then baseline end
    ))
  );
  return jsonb_build_object(
    'edition',next_edition,
    'source',source_value,
    'assignments',assignments,
    'createdAt',now(),
    'planningBaseline',baseline
  );
end$$;

revoke all on function "Basic_Carrier_Record".save_operational_load_plan(text,uuid,integer,text,jsonb,numeric,numeric) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_load_plan(text,uuid,integer,text,jsonb,numeric,numeric) to authenticated;

notify pgrst,'reload schema';
commit;
