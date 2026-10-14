begin;

create or replace function "Basic_Carrier_Record".update_operational_load_reference(
  p_iata text,
  p_operational_flight_id uuid,
  p_edition integer,
  p_load_id text,
  p_reference text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  current_edition integer;
  clean_reference text:=nullif(upper(btrim(coalesce(p_reference,''))), '');
  plan "Basic_Carrier_Record"."Operational_Load_Plan_Editions"%rowtype;
  f "Basic_Carrier_Record"."Operational_Flights"%rowtype;
begin
  p_iata:=upper(btrim(p_iata));
  p_load_id:=btrim(coalesce(p_load_id,''));
  if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then
    raise exception 'Permission denied' using errcode='42501';
  end if;
  if p_edition<1 or p_load_id!~'^PLANNED_BAGGAGE:[0-9]+$' then
    raise exception 'Select a saved baggage ULD' using errcode='22023';
  end if;
  if clean_reference is not null and clean_reference!~'^[A-Z0-9][A-Z0-9-]{2,14}$' then
    raise exception 'Enter a valid baggage ULD number' using errcode='22023';
  end if;
  select*into f from "Basic_Carrier_Record"."Operational_Flights"
    where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
  if not found then raise exception 'Operational flight not found' using errcode='22023';end if;
  select coalesce(max("Edition_Number"),0)into current_edition
    from "Basic_Carrier_Record"."Operational_Load_Plan_Editions"
    where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
  if current_edition<>p_edition then
    raise exception 'The load plan has changed. Reload before updating the ULD number.' using errcode='40001';
  end if;
  select*into plan from "Basic_Carrier_Record"."Operational_Load_Plan_Editions"
    where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id and "Edition_Number"=p_edition for update;
  if not exists(select 1 from jsonb_array_elements(plan."Assignments") item where item->>'loadId'=p_load_id)then
    raise exception 'The baggage ULD is not part of the current load plan' using errcode='22023';
  end if;
  update "Basic_Carrier_Record"."Operational_Load_Plan_Editions" set "Assignments"=(
    select jsonb_agg(
      case when item->>'loadId'=p_load_id then
        case when clean_reference is null then item-'loadReference'
             else jsonb_set(item,'{loadReference}',to_jsonb(clean_reference),true)end
      else item end
      order by ordinal
    ) from jsonb_array_elements(plan."Assignments")with ordinality rows(item,ordinal)
  ) where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id and "Edition_Number"=p_edition;
  insert into "Basic_Carrier_Record"."Operational_Flight_Events"(
    "Operational_Flight_ID","Carrier_IATA","Event_Type","Previous_Status","New_Status","Event_Data","Actor_User_ID"
  )values(
    p_operational_flight_id,p_iata,'UPDATED',f."Status",f."Status",
    jsonb_build_object('action','BAGGAGE_ULD_NUMBER_UPDATED','loadPlanEdition',p_edition,'loadId',p_load_id,'uldNumber',clean_reference),auth.uid()
  );
  return "Basic_Carrier_Record".get_operational_load_plan(p_iata,p_operational_flight_id);
end$$;

revoke all on function "Basic_Carrier_Record".update_operational_load_reference(text,uuid,integer,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".update_operational_load_reference(text,uuid,integer,text,text) to authenticated;

comment on function "Basic_Carrier_Record".update_operational_load_reference(text,uuid,integer,text,text) is
  'Updates baggage ULD identification on the current load-plan edition without changing its loading distribution or edition number.';

notify pgrst,'reload schema';
commit;
