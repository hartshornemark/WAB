begin;

-- Enumerate compatible pallet alternatives, highest pallet count first. For
-- each arrangement, solve the remaining container footprints exactly. The
-- baggage reservation is a feasibility constraint, never optional cargo space.
create or replace function private.a350_pallet_first_capacity(p_pallets jsonb,p_containers jsonb,p_baggage_count integer)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare candidate record;remaining jsonb;containers jsonb;best jsonb;best_pallets integer:=-1;best_containers integer:=-1;net_capacity numeric;best_net numeric:=-1;
begin
 if p_baggage_count is null or p_baggage_count<0 then raise exception 'Check the baggage ULD reservation before calculating the cargo offer' using errcode='23514';end if;
 for candidate in
  with recursive pallets as materialized(
   select value position,n,array(select jsonb_array_elements_text(value->'bays')) bays
   from jsonb_array_elements(p_pallets) with ordinality a(value,n)
  ), layouts(last_n,positions,bays,pallet_count) as(
   select 0::bigint,'[]'::jsonb,array[]::text[],0
   union all
   select p.n,l.positions||jsonb_build_array(p.position),l.bays||p.bays,l.pallet_count+1
   from layouts l join pallets p on p.n>l.last_n and not p.bays&&l.bays
  ) select positions,bays,pallet_count from layouts order by pallet_count desc,positions::text
 loop
  if candidate.pallet_count<best_pallets then exit;end if;
  select coalesce(jsonb_agg(value),'[]'::jsonb) into remaining from jsonb_array_elements(p_containers)
   where not (value->'bays') ?| candidate.bays;
  containers:=private.compatible_baggage_positions(remaining);
  if jsonb_array_length(containers)<p_baggage_count then continue;end if;
  select coalesce(sum((value->>'netWeightCapacity')::numeric),0) into net_capacity from jsonb_array_elements(candidate.positions);
  if best is null or jsonb_array_length(containers)>best_containers
    or (jsonb_array_length(containers)=best_containers and net_capacity>best_net) then
   best:=jsonb_build_object('pallets',candidate.positions,'containers',containers);
   best_pallets:=candidate.pallet_count;best_containers:=jsonb_array_length(containers);best_net:=net_capacity;
  end if;
 end loop;
 if best is null then raise exception 'No compatible cargo arrangement preserves the baggage ULD reservation' using errcode='23514';end if;
 return best;
end $$;
revoke all on function private.a350_pallet_first_capacity(jsonb,jsonb,integer) from public,anon,authenticated;

alter function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid)
 rename to get_operational_freight_planning_without_a350_pallet_first;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning_without_a350_pallet_first(text,uuid) from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".get_operational_freight_planning(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;flight "Basic_Carrier_Record"."Operational_Flights"%rowtype;pallet record;container record;
 pallets jsonb;containers jsonb;layout jsonb;cargo_containers jsonb;allocations jsonb:='[]'::jsonb;reserved integer;
 pallet_count integer;container_count integer;space_weight numeric;space_volume numeric;offer numeric;note text;take integer;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')) then raise exception 'Load Control access denied' using errcode='42501';end if;
 result:="Basic_Carrier_Record".get_operational_freight_planning_without_a350_pallet_first(p_iata,p_operational_flight_id);
 -- Do not change other aircraft or incomplete baggage configuration.
 if result->>'baggageCapacityBasis' is distinct from 'DEFAULT_CONTAINER_CONFIGURATION' then return result;end if;
 if jsonb_array_length(coalesce(result->'baggagePlanningNotes','[]'::jsonb))>0 then return result;end if;
 select * into flight from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 select btrim(s."ULD_ID") code,btrim(s."ULD_Type") type,s."ULD_Tare_Weight"::numeric tare,s."ULD_Max_Weight"::numeric gross,m."ULD_Volume"::numeric volume into pallet
 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
 left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID")
 where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA" and s."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and btrim(s."ULD_Type")='LD7'
 order by s."ULD_Default" desc,btrim(s."ULD_ID") limit 1;
 if pallet.code is null then return result;end if;
 select btrim(s."ULD_ID") code,btrim(s."ULD_Type") type,s."ULD_Tare_Weight"::numeric tare,s."ULD_Max_Weight"::numeric gross,m."ULD_Volume"::numeric volume into container
 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
 left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID")
 where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA" and s."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and btrim(s."ULD_ID")=result->>'uldCode';
 if pallet.tare is null or pallet.tare<0 or pallet.gross is null or pallet.gross<=pallet.tare or pallet.volume is null or pallet.volume<=0 then
  note:='Complete the configured cargo pallet tare, gross-weight and volume limits';
 end if;
 if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
   and p."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Code")=pallet.code
   and (p."ULD_Position_Max_Weight" is null or p."ULD_Position_Max_Weight"<=pallet.tare or not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" o where o."ULD_Position_UUID"=p."ULD_Position_UUID"))) then
  note:='Complete the cargo pallet D3 weight limits and occupancy mappings';
 end if;
 if note is not null then return result||jsonb_build_object('ready',false,'cargoOfferWeight',null,'baggagePlanningNotes',jsonb_build_array(note),'missing',coalesce(result->'missing','[]'::jsonb)||jsonb_build_array(note));end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p."ULD_Position_UUID",'uldCode',btrim(p."ULD_Code"),'netWeightCapacity',greatest(0,least(p."ULD_Position_Max_Weight"::numeric,case when btrim(p."ULD_Code")=pallet.code then pallet.gross else container.gross end)-case when btrim(p."ULD_Code")=pallet.code then pallet.tare else container.tare end),
  'bays',(select jsonb_agg(p."Hold_Name_ID"||':'||o."Atomic_Bay_ID") from "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" o where o."ULD_Position_UUID"=p."ULD_Position_UUID")) order by p."ULD_Position_UUID"),'[]'::jsonb)
 into containers from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
  and p."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Code") in(pallet.code,container.code);
 select coalesce(jsonb_agg(value),'[]'::jsonb) into pallets from jsonb_array_elements(containers) where value->>'uldCode'=pallet.code;
 select coalesce(jsonb_agg(value),'[]'::jsonb) into containers from jsonb_array_elements(containers) where value->>'uldCode'=container.code;
 reserved:=coalesce((result->'baggageCapacityReservation'->>'uldCount')::integer,(result->>'plannedBaggageUldPositions')::integer,0);
 layout:=private.a350_pallet_first_capacity(pallets,containers,reserved);
 pallet_count:=jsonb_array_length(layout->'pallets');container_count:=jsonb_array_length(layout->'containers')-reserved;
 -- Reserve baggage in the lowest-capacity compatible container slots, leaving
 -- a conservative explicit cargo witness. These are not loading assignments.
 select coalesce(jsonb_agg(value order by (value->>'netWeightCapacity')::numeric desc,value->>'id'),'[]'::jsonb) into cargo_containers from
  (select value from jsonb_array_elements(layout->'containers') order by (value->>'netWeightCapacity')::numeric desc,value->>'id' limit container_count) c;
 select coalesce(sum((value->>'netWeightCapacity')::numeric),0) into space_weight from jsonb_array_elements((layout->'pallets')||cargo_containers);
 space_weight:=greatest(0,least(space_weight+coalesce((result->>'availableBulkWeight')::numeric,0),
  (result->>'holdWeightCapacity')::numeric-coalesce((result->>'plannedBaggageWeight')::numeric,0)-reserved*container.tare));
 space_volume:=pallet_count*pallet.volume+container_count*container.volume+coalesce((result->>'availableBulkVolume')::numeric,0);
 offer:=least((result->>'remainingPayload')::numeric,space_weight);
 if pallet_count>0 then allocations:=allocations||jsonb_build_array(jsonb_build_object('kind','PALLET','uldType',pallet.type,'uldCode',pallet.code,'positionCount',pallet_count));end if;
 if container_count>0 then allocations:=allocations||jsonb_build_array(jsonb_build_object('kind','CONTAINER','uldType',container.type,'uldCode',container.code,'positionCount',container_count));end if;
 return result||jsonb_build_object('cargoCapacityBasis','PALLET_FIRST','cargoUldAllocations',allocations,'availableUldPositions',container_count,
  'cargoCapacityPositions',jsonb_build_object('pallets',layout->'pallets','containers',cargo_containers,'baggageContainerCount',reserved,'allContainerPositions',layout->'containers'),
  'spaceWeightCapacity',space_weight,'remainingHoldWeight',space_weight,'remainingHoldVolume',round(space_volume,2),'totalAvailableCargoVolume',round(space_volume,2),
  'cargoOfferWeight',case when (result->>'ready')::boolean then offer else null end,'limitingFactor',case when offer=(result->>'remainingPayload')::numeric then 'PAYLOAD' else 'HOLD_WEIGHT' end);
end $$;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
