begin;

create or replace function "Basic_Carrier_Record".save_aircraft_d4(
  p_iata text,
  p_type_code text,
  p_subtype text,
  p_revision text,
  p_doors jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  current_data jsonb;
  item jsonb;
  hold_id text;
  forward_arm double precision;
  aft_arm double precision;
  door_height double precision;
  door_orientation text;
begin
  if not (
    private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT')
    or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')
  ) then
    raise exception 'Not authorised' using errcode='42501';
  end if;

  current_data:="Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st);
  if current_data->>'revision'<>p_revision then
    raise exception 'Conflict' using errcode='40001';
  end if;
  if not (current_data->>'doorsActive')::boolean then
    raise exception 'D4 Doors are optional and not selected' using errcode='23514';
  end if;
  if jsonb_typeof(p_doors)<>'array' or jsonb_array_length(p_doors)<>(
    select count(*)
    from "Basic_Carrier_Record"."Aircraft_Holds"
    where "Carrier_IATA"=p_iata
      and "Aircraft_Type_IATA"=tc
      and "Aircraft_Series_Subtype"=st
      and coalesce("Hold_Has_Door",true)
  ) then
    raise exception 'Every hold requires one door' using errcode='22023';
  end if;

  for item in select value from jsonb_array_elements(p_doors) loop
    hold_id:=upper(btrim(item->>'holdId'));
    forward_arm:=(item->>'forwardArm')::double precision;
    aft_arm:=(item->>'aftArm')::double precision;
    door_height:=(item->>'height')::double precision;
    door_orientation:=upper(btrim(item->>'orientation'));

    if not exists (
      select 1
      from "Basic_Carrier_Record"."Aircraft_Holds"
      where "Carrier_IATA"=p_iata
        and "Aircraft_Type_IATA"=tc
        and "Aircraft_Series_Subtype"=st
        and btrim("Hold_Name_ID")=hold_id
        and coalesce("Hold_Has_Door",true)
    ) then
      raise exception 'Unknown hold' using errcode='23503';
    end if;

    update "Basic_Carrier_Record"."Aircraft_Holds"
    set
      "Hold_DOOR_Start"=forward_arm,
      "Hold_DOOR_End"=aft_arm,
      "Hold_DOOR_Height"=door_height,
      "Hold_DOOR_Orientation"=door_orientation
    where "Carrier_IATA"=p_iata
      and "Aircraft_Type_IATA"=tc
      and "Aircraft_Series_Subtype"=st
      and btrim("Hold_Name_ID")=hold_id
      and coalesce("Hold_Has_Door",true)
      and (
        "Hold_DOOR_Start" is distinct from forward_arm
        or "Hold_DOOR_End" is distinct from aft_arm
        or "Hold_DOOR_Height" is distinct from door_height
        or "Hold_DOOR_Orientation" is distinct from door_orientation
      );
  end loop;

  return "Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st);
end
$function$;

notify pgrst,'reload schema';

commit;
