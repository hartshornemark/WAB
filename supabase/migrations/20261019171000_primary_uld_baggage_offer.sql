begin;

alter function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid)
  rename to get_operational_freight_planning_without_primary_uld;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning_without_primary_uld(text,uuid)
  from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".get_operational_freight_planning(
  p_iata text,
  p_operational_flight_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  result jsonb;
  flight "Basic_Carrier_Record"."Operational_Flights"%rowtype;
  primary_uld_type text;
  primary_uld_code text;
  primary_position_count integer:=0;
  uld_tare numeric:=0;
  uld_max_weight numeric:=0;
  uld_volume numeric:=0;
  baggage_pieces integer:=0;
  baggage_weight numeric:=0;
  average_piece_weight numeric:=0;
  configured_piece_volume numeric;
  weight_piece_capacity integer;
  volume_piece_capacity integer;
  piece_capacity integer;
  planned_uld_count integer:=0;
  available_uld_count integer:=0;
  bulk_planning_weight numeric:=0;
  bulk_volume numeric:=0;
  available_space_weight numeric:=0;
  available_volume numeric:=0;
  remaining_payload numeric;
  cargo_offer numeric;
  limiting_factor text;
begin
  p_iata:=upper(btrim(p_iata));
  result:="Basic_Carrier_Record".get_operational_freight_planning_without_primary_uld(p_iata,p_operational_flight_id);
  if result->>'operatingRole'='FREIGHTER' then return result;end if;

  select * into flight
  from "Basic_Carrier_Record"."Operational_Flights"
  where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;

  select q.uld_type,q.uld_code,q.position_count
  into primary_uld_type,primary_uld_code,primary_position_count
  from(
    select btrim(p."ULD_Type") uld_type,btrim(p."ULD_Code") uld_code,count(*)::integer position_count
    from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
    where p."Carrier_IATA"=p_iata
      and p."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
      and p."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype"
      and p."ULD_Row_Type"='POSITION'
    group by btrim(p."ULD_Type"),btrim(p."ULD_Code")
    order by count(*) desc,btrim(p."ULD_Type"),btrim(p."ULD_Code")
    limit 1
  )q;

  if primary_uld_code is null then return result;end if;

  select s."ULD_Tare_Weight",s."ULD_Max_Weight",m."ULD_Volume"
  into uld_tare,uld_max_weight,uld_volume
  from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
  left join "Basic_Carrier_Record"."MASTER_ULD_List" m
    on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID")
  where s."Carrier_IATA"=p_iata
    and s."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
    and s."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype"
    and btrim(s."ULD_ID")=primary_uld_code
  limit 1;

  baggage_pieces:=coalesce(nullif(result->>'plannedBaggagePieces','')::integer,0);
  baggage_weight:=coalesce(nullif(result->>'plannedBaggageWeight','')::numeric,0);
  average_piece_weight:=case when baggage_pieces>0 then baggage_weight/baggage_pieces else 0 end;
  if average_piece_weight>0 and uld_max_weight>uld_tare then
    weight_piece_capacity:=floor((uld_max_weight-uld_tare)/average_piece_weight)::integer;
  end if;

  select max(p."Average_Bag_Volume")
  into configured_piece_volume
  from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p
  where p."Carrier_IATA"=p_iata and p."Average_Bag_Volume">0
    and (p."Class_Code" is null or exists(
      select 1 from jsonb_array_elements(coalesce(result->'baggageClasses','[]'::jsonb)) c
      where c->>'classCode'=p."Class_Code"
    ));
  if configured_piece_volume>0 and uld_volume>0 then
    volume_piece_capacity:=floor(uld_volume/configured_piece_volume)::integer;
  end if;
  piece_capacity:=case
    when weight_piece_capacity>0 and volume_piece_capacity>0 then least(weight_piece_capacity,volume_piece_capacity)
    when volume_piece_capacity>0 then volume_piece_capacity
    when weight_piece_capacity>0 then weight_piece_capacity
    else null
  end;

  planned_uld_count:=case when baggage_pieces>0 and piece_capacity>0
    then least(primary_position_count,ceil(baggage_pieces::numeric/piece_capacity)::integer)
    else 0 end;
  available_uld_count:=greatest(0,primary_position_count-planned_uld_count);
  bulk_planning_weight:=coalesce(nullif(result->>'availableBulkWeight','')::numeric,0);
  bulk_volume:=coalesce(nullif(result->>'availableBulkVolume','')::numeric,0);
  available_space_weight:=available_uld_count*greatest(0,uld_max_weight-uld_tare)+bulk_planning_weight;
  available_volume:=available_uld_count*coalesce(uld_volume,0)+bulk_volume;
  remaining_payload:=nullif(result->>'remainingPayload','')::numeric;
  cargo_offer:=least(remaining_payload,available_space_weight);
  limiting_factor:=case when cargo_offer=remaining_payload then 'PAYLOAD' else 'HOLD_WEIGHT' end;

  return result||jsonb_build_object(
    'uldCode',primary_uld_code,
    'primaryUldType',primary_uld_type,
    'uldPositionCount',primary_position_count,
    'baggagePiecesPerUld',piece_capacity,
    'plannedBaggageUldPositions',planned_uld_count,
    'availableUldPositions',available_uld_count,
    'spaceWeightCapacity',available_space_weight,
    'remainingHoldWeight',available_space_weight,
    'remainingHoldVolume',round(available_volume,2),
    'totalAvailableCargoVolume',round(available_volume,2),
    'cargoOfferWeight',cargo_offer,
    'limitingFactor',limiting_factor
  );
end
$$;

revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
