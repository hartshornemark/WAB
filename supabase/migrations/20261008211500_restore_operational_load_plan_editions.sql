begin;

create or replace function "Basic_Carrier_Record".get_operational_load_plan(p_iata text,p_operational_flight_id uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare p "Basic_Carrier_Record"."Operational_Load_Plan_Editions"%rowtype;
begin
 if not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW')or private.has_global_permission('LOAD_CONTROL_VIEW'))then raise exception 'Permission denied' using errcode='42501';end if;
 select*into p from "Basic_Carrier_Record"."Operational_Load_Plan_Editions" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id order by "Edition_Number" desc limit 1;
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
  'createdAt',p."Created_At"
 );
end$$;

notify pgrst,'reload schema';
commit;
