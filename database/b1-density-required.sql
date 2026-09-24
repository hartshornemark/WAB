-- B1 commodity densities are required operational data.
-- Preserve existing values while preventing incomplete density sets from being saved.
begin;

create or replace function "Basic_Carrier_Record".get_carrier_densities(p_iata text) returns jsonb
language sql stable security invoker set search_path='' as $$
with access as (
  select private.can_edit_carrier_details(p_iata) as edit,
         private.can_view_carrier_classes(p_iata) as view
)
select jsonb_build_object(
  'canView',a.view,
  'canEdit',a.edit,
  'exists',d."Carrier_IATA" is not null,
  'revision',case when a.view then md5(
    coalesce(to_jsonb(d)::text,'null') ||
    coalesce(d.xmin::text,'') ||
    jsonb_build_array(
      b."Carrier_Unit_Weight_KG",
      b."Carrier_Unit_Weight_LB",
      b."Carrier_Unit_Volume_m3",
      b."Carrier_Unit_Volume_ft3"
    )::text
  ) else '' end,
  'weightUnit',case
    when b."Carrier_Unit_Weight_KG" and not b."Carrier_Unit_Weight_LB" then 'KG'
    when b."Carrier_Unit_Weight_LB" and not b."Carrier_Unit_Weight_KG" then 'LB'
    else ''
  end,
  'volumeUnit',case
    when b."Carrier_Unit_Volume_m3" and not b."Carrier_Unit_Volume_ft3" then 'm3'
    when b."Carrier_Unit_Volume_ft3" and not b."Carrier_Unit_Volume_m3" then 'ft3'
    else ''
  end,
  'values',jsonb_build_object(
    'baggage',coalesce(d."Density_Checked_Baggage"::text,''),
    'cargo',coalesce(d."Density_General_Cargo"::text,''),
    'mail',coalesce(d."Density_General_Mail"::text,'')
  )
)
from access a
left join "Basic_Carrier_Record"."Carrier_Units_of_Measure" d
  on a.view and d."Carrier_IATA"=p_iata
left join "Basic_Carrier_Record"."Basic_Carrier_Data" b
  on a.view and b."Carrier_IATA"=p_iata;
$$;

create or replace function "Basic_Carrier_Record".save_carrier_densities(
  p_iata text,
  p_revision text,
  p_values jsonb
) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
  current_data jsonb;
  key text;
  val text;
begin
  if not private.can_edit_carrier_details(p_iata) then
    raise exception 'Not authorised' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('b1-densities:'||p_iata,0));
  perform 1
  from "Basic_Carrier_Record"."Basic_Carrier_Data"
  where "Carrier_IATA"=p_iata
  for update;
  if not found then
    raise exception 'Set carrier units first' using errcode='23514';
  end if;

  perform 1
  from "Basic_Carrier_Record"."Carrier_Units_of_Measure"
  where "Carrier_IATA"=p_iata
  for update;

  current_data:="Basic_Carrier_Record".get_carrier_densities(p_iata);
  if p_revision is distinct from current_data->>'revision' then
    raise exception 'Density settings changed' using errcode='40001';
  end if;
  if current_data->>'weightUnit'='' or current_data->>'volumeUnit'='' then
    raise exception 'Set weight and volume units first' using errcode='23514';
  end if;
  if jsonb_typeof(p_values) is distinct from 'object' then
    raise exception 'All three density values are required' using errcode='22023';
  end if;

  foreach key in array array['baggage','cargo','mail'] loop
    val:=p_values->>key;
    if val is null or jsonb_typeof(p_values->key)<>'string' or val='' then
      raise exception 'All three density values must be positive numbers' using errcode='22023';
    end if;
    if val !~ '^[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$' then
      raise exception 'All three density values must be positive numbers' using errcode='22023';
    end if;
    if val::float8<=0 or val::float8>='Infinity'::float8 then
      raise exception 'All three density values must be positive numbers' using errcode='22023';
    end if;
  end loop;

  insert into "Basic_Carrier_Record"."Carrier_Units_of_Measure"(
    "Carrier_IATA",
    "Density_Checked_Baggage",
    "Density_General_Cargo",
    "Density_General_Mail"
  ) values(
    p_iata,
    (p_values->>'baggage')::float8,
    (p_values->>'cargo')::float8,
    (p_values->>'mail')::float8
  )
  on conflict("Carrier_IATA") do update set
    "Density_Checked_Baggage"=excluded."Density_Checked_Baggage",
    "Density_General_Cargo"=excluded."Density_General_Cargo",
    "Density_General_Mail"=excluded."Density_General_Mail";

  return "Basic_Carrier_Record".get_carrier_densities(p_iata);
end $$;

revoke all on function "Basic_Carrier_Record".get_carrier_densities(text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_carrier_densities(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_densities(text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_carrier_densities(text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
