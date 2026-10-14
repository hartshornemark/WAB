begin;

create or replace function "Basic_Carrier_Record".save_operational_flight_delay(
  p_iata text,
  p_operational_flight_id uuid,
  p_expected_version integer,
  p_delay_minutes integer
)
returns jsonb
language plpgsql
security invoker
set search_path=''
as $$
declare f record;
begin
  if not (
    private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')
    or private.has_global_permission('LOAD_CONTROL_OPERATE')
  ) then
    raise exception 'Not authorised' using errcode='42501';
  end if;

  if p_delay_minutes is null or p_delay_minutes not between 0 and 2880 then
    raise exception 'Delay must be between 0 and 2880 minutes' using errcode='23514';
  end if;

  select * into f
  from "Basic_Carrier_Record"."Operational_Flights"
  where "Carrier_IATA"=p_iata
    and "Operational_Flight_ID"=p_operational_flight_id
  for update;

  if not found then
    raise exception 'Operational flight not found' using errcode='P0002';
  end if;
  if f."Version"<>p_expected_version then
    raise exception 'The operational flight changed while you were editing' using errcode='PT409';
  end if;

  update "Basic_Carrier_Record"."Operational_Flights"
  set "Delay_Minutes"=p_delay_minutes,
      "Version"="Version"+1,
      "Updated_At"=now()
  where "Carrier_IATA"=p_iata
    and "Operational_Flight_ID"=p_operational_flight_id;

  insert into "Basic_Carrier_Record"."Operational_Flight_Events"(
    "Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data","Actor_User_ID"
  ) values(
    p_operational_flight_id,p_iata,'DELAY_UPDATED',f."Status",f."Status",
    jsonb_build_object('previousDelayMinutes',f."Delay_Minutes",'delayMinutes',p_delay_minutes),auth.uid()
  );

  return "Basic_Carrier_Record".get_operational_flight_delay(p_iata,p_operational_flight_id);
end
$$;

revoke all on function "Basic_Carrier_Record".save_operational_flight_delay(text,uuid,integer,integer) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_flight_delay(text,uuid,integer,integer) to authenticated;

notify pgrst,'reload schema';
commit;
