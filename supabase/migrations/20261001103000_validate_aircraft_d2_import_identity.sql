begin;

drop function if exists "Basic_Carrier_Record".import_aircraft_d2(text,text,text,text,jsonb,jsonb);

create function "Basic_Carrier_Record".import_aircraft_d2(
  p_iata text,
  p_type_code text,
  p_subtype text,
  p_revision text,
  p_source_type_code text,
  p_source_subtype text,
  p_bulk jsonb,
  p_uld jsonb
) returns jsonb
language plpgsql
security invoker
set search_path=''
as $$
declare
  result jsonb;
  next_revision text:=p_revision;
  target_type text:=upper(btrim(p_type_code));
  target_subtype text:=upper(btrim(p_subtype));
begin
  if upper(btrim(coalesce(p_source_type_code,'')))<>target_type
    or upper(btrim(coalesce(p_source_subtype,'')))<>target_subtype then
    raise exception 'CSV aircraft does not match the target aircraft' using errcode='22023';
  end if;

  if p_bulk is null and p_uld is null then
    raise exception 'D2 import is empty' using errcode='22023';
  end if;

  if p_bulk is not null then
    result:="Basic_Carrier_Record".save_aircraft_d2(
      p_iata,target_type,target_subtype,next_revision,'BULK',p_bulk
    );
    next_revision:=result->>'revision';
  end if;

  if p_uld is not null then
    result:="Basic_Carrier_Record".save_aircraft_d2(
      p_iata,target_type,target_subtype,next_revision,'ULD',p_uld
    );
  end if;

  return result;
end
$$;

revoke all on function "Basic_Carrier_Record".import_aircraft_d2(text,text,text,text,text,text,jsonb,jsonb) from public;
grant execute on function "Basic_Carrier_Record".import_aircraft_d2(text,text,text,text,text,text,jsonb,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
