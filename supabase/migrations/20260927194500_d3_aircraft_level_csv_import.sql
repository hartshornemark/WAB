begin;

create or replace function "Basic_Carrier_Record".import_aircraft_d3_configurations(
  p_iata text,
  p_type_code text,
  p_subtype text,
  p_revision text,
  p_values jsonb
) returns jsonb
language plpgsql
security invoker
set search_path=''
as $$
declare
  item jsonb;
  current_data jsonb;
  current_revision text := p_revision;
  hold_id text;
  configuration_code text;
  original_code text;
begin
  if p_values is null or jsonb_typeof(p_values) <> 'array' or jsonb_array_length(p_values) = 0 then
    raise exception 'Invalid D3 aircraft import' using errcode='22023';
  end if;

  current_data := "Basic_Carrier_Record".get_aircraft_d3(p_iata, p_type_code, p_subtype);
  if current_revision is distinct from current_data->>'revision' then
    raise exception 'Aircraft D3 changed' using errcode='40001';
  end if;

  for item in select value from jsonb_array_elements(p_values) loop
    hold_id := upper(btrim(item->>'holdId'));
    configuration_code := upper(btrim(item->>'code'));
    original_code := case when exists(
      select 1
      from "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" c
      where c."Carrier_IATA" = p_iata
        and c."Aircraft_Type_IATA" = upper(btrim(p_type_code))
        and c."Aircraft_Series_Subtype" = upper(btrim(p_subtype))
        and c."Hold_Name_ID" = hold_id
        and c."ULD_Configuration_Code" = configuration_code
    ) then configuration_code else null end;

    current_data := "Basic_Carrier_Record".save_aircraft_d3_configuration(
      p_iata,
      p_type_code,
      p_subtype,
      current_revision,
      original_code,
      item
    );
    current_revision := current_data->>'revision';
  end loop;

  return current_data;
end
$$;

notify pgrst,'reload schema';
commit;
