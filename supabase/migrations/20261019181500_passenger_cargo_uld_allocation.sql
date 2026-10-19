begin;

alter function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid)
  rename to get_operational_freight_planning_without_cargo_uld_allocation;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning_without_cargo_uld_allocation(text,uuid)
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
  baggage_code text;
  baggage_type text;
  baggage_positions integer:=0;
  baggage_planned integer:=0;
  baggage_available integer:=0;
  baggage_tare numeric:=0;
  baggage_max numeric:=0;
  baggage_volume numeric:=0;
  pallet_code text;
  pallet_type text:='LD7';
  pallet_positions integer:=0;
  pallet_tare numeric:=0;
  pallet_max numeric:=0;
  pallet_volume numeric:=0;
  bulk_weight numeric:=0;
  bulk_volume numeric:=0;
  volume_unit text:='M3';
  bulk_volume_m3 numeric:=0;
  available_space_weight numeric:=0;
  available_volume_m3 numeric:=0;
  remaining_payload numeric;
  cargo_offer numeric;
  allocations jsonb:='[]'::jsonb;
begin
  p_iata:=upper(btrim(p_iata));
  result:="Basic_Carrier_Record".get_operational_freight_planning_without_cargo_uld_allocation(p_iata,p_operational_flight_id);
  if result->>'operatingRole'='FREIGHTER' then return result;end if;

  select * into flight
  from "Basic_Carrier_Record"."Operational_Flights"
  where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;

  baggage_code:=nullif(result->>'uldCode','');
  select btrim(s."ULD_Type"),s."ULD_Tare_Weight",s."ULD_Max_Weight",m."ULD_Volume"
  into baggage_type,baggage_tare,baggage_max,baggage_volume
  from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
  left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID")
  where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
    and s."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and btrim(s."ULD_ID")=baggage_code
  limit 1;

  select btrim(s."ULD_ID"),s."ULD_Tare_Weight",s."ULD_Max_Weight",m."ULD_Volume"
  into pallet_code,pallet_tare,pallet_max,pallet_volume
  from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
  left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID")
  where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
    and s."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and btrim(s."ULD_Type")=pallet_type
  order by (btrim(s."ULD_ID")='P1P') desc,s."ULD_Default" desc,btrim(s."ULD_ID")
  limit 1;

  if pallet_code is not null then
    select count(distinct p."ULD_Position_UUID")::integer into pallet_positions
    from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
    where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
      and p."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype"
      and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Type")=pallet_type;
  end if;

  if baggage_code is not null then
    select count(distinct container."ULD_Position_UUID")::integer into baggage_positions
    from "Basic_Carrier_Record"."Carrier_ULD_Positions" container
    where container."Carrier_IATA"=p_iata and container."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
      and container."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype"
      and container."ULD_Row_Type"='POSITION' and btrim(container."ULD_Code")=baggage_code
      and not exists(
        select 1
        from "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" container_bay
        join "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" pallet_bay
          on pallet_bay."Carrier_IATA"=container_bay."Carrier_IATA"
         and pallet_bay."Aircraft_Type_IATA"=container_bay."Aircraft_Type_IATA"
         and pallet_bay."Aircraft_Series_Subtype"=container_bay."Aircraft_Series_Subtype"
         and pallet_bay."ULD_Configuration_Code"=container_bay."ULD_Configuration_Code"
         and pallet_bay."Atomic_Bay_ID"=container_bay."Atomic_Bay_ID"
        join "Basic_Carrier_Record"."Carrier_ULD_Positions" pallet
          on pallet."ULD_Position_UUID"=pallet_bay."ULD_Position_UUID"
        where container_bay."ULD_Position_UUID"=container."ULD_Position_UUID"
          and pallet."ULD_Row_Type"='POSITION' and btrim(pallet."ULD_Type")=pallet_type
      );
  end if;

  baggage_planned:=least(baggage_positions,coalesce(nullif(result->>'plannedBaggageUldPositions','')::integer,0));
  baggage_available:=greatest(0,baggage_positions-baggage_planned);
  bulk_weight:=coalesce(nullif(result->>'availableBulkWeight','')::numeric,0);
  bulk_volume:=coalesce(nullif(result->>'availableBulkVolume','')::numeric,0);
  select coalesce(c."Volume_Unit",'M3') into volume_unit
  from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" c
  where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
    and c."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype";
  bulk_volume_m3:=case when volume_unit='FT3' then bulk_volume*0.028316846592 else bulk_volume end;

  available_space_weight:=pallet_positions*greatest(0,pallet_max-pallet_tare)
    +baggage_available*greatest(0,baggage_max-baggage_tare)+bulk_weight;
  available_volume_m3:=pallet_positions*coalesce(pallet_volume,0)
    +baggage_available*coalesce(baggage_volume,0)+bulk_volume_m3;
  remaining_payload:=nullif(result->>'remainingPayload','')::numeric;
  cargo_offer:=least(remaining_payload,available_space_weight);

  if pallet_positions>0 then allocations:=allocations||jsonb_build_array(jsonb_build_object(
    'kind','PALLET','uldType',pallet_type,'uldCode',pallet_code,'positionCount',pallet_positions));end if;
  if baggage_available>0 then allocations:=allocations||jsonb_build_array(jsonb_build_object(
    'kind','CONTAINER','uldType',baggage_type,'uldCode',baggage_code,'positionCount',baggage_available));end if;

  return result||jsonb_build_object(
    'uldPositionCount',baggage_positions,
    'plannedBaggageUldPositions',baggage_planned,
    'availableUldPositions',baggage_available,
    'cargoUldAllocations',allocations,
    'availableBulkVolumeUnit',volume_unit,
    'spaceWeightCapacity',available_space_weight,
    'remainingHoldWeight',available_space_weight,
    'remainingHoldVolume',round(available_volume_m3,2),
    'totalAvailableCargoVolume',round(available_volume_m3,2),
    'cargoOfferWeight',cargo_offer,
    'limitingFactor',case when cargo_offer=remaining_payload then 'PAYLOAD' else 'HOLD_WEIGHT' end
  );
end
$$;

revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;
notify pgrst,'reload schema';

commit;
