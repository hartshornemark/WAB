-- Preserve previously configured C8 By Tank records when upgrading to the
-- explicit tank-weight list.  The earlier model stored maximum volume and
-- source specific gravity; their product is the tank's maximum weight.
update "Basic_Carrier_Record"."Aircraft_Fuel_Loading_METHODS" as methods
set "Tanks" = (
  select jsonb_agg(
    case
      when jsonb_array_length(coalesce(tank.value->'weights','[]'::jsonb)) = 0
       and nullif(tank.value->>'maximumVolume','') is not null
       and nullif(tank.value->>'sourceSpecificGravity','') is not null
      then jsonb_set(
        tank.value,
        '{weights}',
        jsonb_build_array(ceil(
          (tank.value->>'maximumVolume')::numeric
          * (tank.value->>'sourceSpecificGravity')::numeric
        )::bigint),
        true
      )
      else tank.value
    end
    order by tank.ordinality
  )
  from jsonb_array_elements(methods."Tanks") with ordinality as tank(value,ordinality)
)
where methods."By_Tank"
  and exists (
    select 1
    from jsonb_array_elements(methods."Tanks") as tank(value)
    where jsonb_array_length(coalesce(tank.value->'weights','[]'::jsonb)) = 0
      and nullif(tank.value->>'maximumVolume','') is not null
      and nullif(tank.value->>'sourceSpecificGravity','') is not null
  );
