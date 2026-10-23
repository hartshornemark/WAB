begin;

-- Maximum-cardinality compatible set, not a count of alternative rows.
-- Branch only on conflicting positions; isolated positions return immediately.
create or replace function private.compatible_baggage_positions(p_positions jsonb)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare pivot jsonb;included jsonb;excluded jsonb;remaining jsonb;
begin
 select a.value into pivot from jsonb_array_elements(p_positions) a
 join jsonb_array_elements(p_positions) b on a.value->>'id'<>b.value->>'id'
  and (a.value->'bays') ?| array(select jsonb_array_elements_text(b.value->'bays'))
 group by a.value order by count(*) desc,a.value->>'id' limit 1;
 if not found then return p_positions;end if;
 select coalesce(jsonb_agg(value),'[]'::jsonb) into remaining from jsonb_array_elements(p_positions)
  where value->>'id'<>pivot->>'id' and not ((value->'bays') ?| array(select jsonb_array_elements_text(pivot->'bays')));
 included:=jsonb_build_array(pivot)||private.compatible_baggage_positions(remaining);
 select coalesce(jsonb_agg(value),'[]'::jsonb) into remaining from jsonb_array_elements(p_positions) where value->>'id'<>pivot->>'id';
 excluded:=private.compatible_baggage_positions(remaining);
 if jsonb_array_length(included)>=jsonb_array_length(excluded) then return included;end if;
 return excluded;
end $$;
revoke all on function private.compatible_baggage_positions(jsonb) from public,anon,authenticated;

-- Pure packing policy. It creates quantities, never aircraft positions.
-- BF/BJ share only if their complete aggregate fits one configured ULD.
create or replace function private.a350_baggage_piece_targets(
 p_classes jsonb,p_piece_limit integer,p_net_limit numeric,p_volume_limit numeric
) returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare
 row jsonb; premium_pieces integer; premium_weight numeric; premium_volume numeric;
 combine_premium boolean; pieces integer; weight numeric; volume numeric;
 capacity integer; remaining integer; targets jsonb:='[]'::jsonb;
begin
 if p_piece_limit is null or p_piece_limit<=0 or p_net_limit is null or p_net_limit<=0
   or p_volume_limit is null or p_volume_limit<=0 then
  raise exception 'Configure the default baggage ULD piece, gross-weight, tare and volume limits' using errcode='23514';
 end if;
 for row in select value from jsonb_array_elements(p_classes) loop
  if nullif(row->>'plannedPieces','') is null or (row->>'plannedPieces')::integer<0
    or nullif(row->>'plannedWeight','') is null or (row->>'plannedWeight')::numeric<0
    or ((row->>'plannedPieces')::integer=0 and (row->>'plannedWeight')::numeric>0)
    or ((row->>'plannedPieces')::integer>0 and
      (nullif(row->>'plannedVolume','') is null or (row->>'plannedVolume')::numeric<=0
       or (row->>'plannedWeight')::numeric<=0)) then
   raise exception 'Complete the baggage pieces, net weight and volume forecast for each active class' using errcode='23514';
  end if;
 end loop;
 select coalesce(sum((value->>'plannedPieces')::integer),0),coalesce(sum((value->>'plannedWeight')::numeric),0),coalesce(sum((value->>'plannedVolume')::numeric),0)
 into premium_pieces,premium_weight,premium_volume from jsonb_array_elements(p_classes)
 where value->>'commodityCode' in('BF','BJ');
 combine_premium:=premium_pieces>0 and premium_pieces<=p_piece_limit
   and premium_weight<=p_net_limit and premium_volume<=p_volume_limit;
 if combine_premium then targets:=jsonb_build_array(premium_pieces);end if;
 for row in select value from jsonb_array_elements(p_classes) loop
  if combine_premium and row->>'commodityCode' in('BF','BJ') then continue;end if;
  pieces:=(row->>'plannedPieces')::integer;
  if pieces=0 then continue;end if;
  weight:=(row->>'plannedWeight')::numeric;volume:=(row->>'plannedVolume')::numeric;
  capacity:=least(p_piece_limit,floor(p_net_limit*pieces/weight)::integer,floor(p_volume_limit*pieces/volume)::integer);
  -- Commodity weights are rounded to whole kg when contents are generated.
  while capacity>0 and ceil(capacity*weight/pieces)>p_net_limit loop capacity:=capacity-1;end loop;
  if capacity<=0 then raise exception 'A forecast baggage piece exceeds the default ULD weight or volume limit' using errcode='23514';end if;
  remaining:=pieces;
  while remaining>0 loop targets:=targets||jsonb_build_array(least(capacity,remaining));remaining:=remaining-least(capacity,remaining);end loop;
 end loop;
 return targets;
end $$;
revoke all on function private.a350_baggage_piece_targets(jsonb,integer,numeric,numeric) from public,anon,authenticated;

-- One content validator serves both saved-state review and manual acceptance.
create or replace function private.a350_baggage_contents_summary(p_planning jsonb,p_values jsonb)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare item jsonb;commodity jsonb;forecast jsonb;volume numeric;bulk_volume numeric:=0;bulk_weight numeric:=0;pieces numeric;weight numeric;max_bulk_volume numeric;max_bulk_weight numeric;uld_count integer:=0;uld_weight numeric:=0;
begin
 if jsonb_typeof(p_values->'contents') is distinct from 'array' then raise exception 'Complete the planned baggage contents' using errcode='23514';end if;
  for item in select value from jsonb_array_elements(p_values->'contents') loop
   if item->>'kind' not in('ULD','BULK') or nullif(item->>'pieces','') is null or (item->>'pieces')::integer<0 or nullif(item->>'netWeight','') is null or (item->>'netWeight')::numeric<0
     or jsonb_typeof(item->'commodities') is distinct from 'array' or jsonb_array_length(item->'commodities')=0 then
    raise exception 'Complete each baggage load and its category breakdown' using errcode='23514';
   end if;
   if (select coalesce(sum((value->>'pieces')::integer),0) from jsonb_array_elements(item->'commodities'))<>(item->>'pieces')::integer
     or abs((select coalesce(sum((value->>'netWeight')::numeric),0) from jsonb_array_elements(item->'commodities'))-(item->>'netWeight')::numeric)>0.5 then
    raise exception 'Reconcile each baggage load with its category breakdown' using errcode='23514';
   end if;
   volume:=0;
   for commodity in select value from jsonb_array_elements(item->'commodities') loop
    if nullif(commodity->>'pieces','') is null or (commodity->>'pieces')::integer<0 or nullif(commodity->>'netWeight','') is null or (commodity->>'netWeight')::numeric<0 then
     raise exception 'Check each baggage category quantity and net weight' using errcode='23514';
    end if;
    select value into forecast from jsonb_array_elements(p_planning->'baggageClasses')
      where value->>'classCode'=commodity->>'classCode' and value->>'commodityCode'=commodity->>'commodityCode';
    if not found or (forecast->>'plannedPieces')::numeric<=0 then raise exception 'Identify every planned baggage commodity against its forecast class' using errcode='23514';end if;
    volume:=volume+(commodity->>'pieces')::numeric*(forecast->>'plannedVolume')::numeric/(forecast->>'plannedPieces')::numeric;
   end loop;
   if item->>'kind'='ULD' then
    uld_count:=uld_count+1;uld_weight:=uld_weight+(item->>'netWeight')::numeric;
    if (item->>'pieces')::integer<=0 or (item->>'netWeight')::numeric<=0 or (item->>'pieces')::integer>(p_planning->>'baggagePiecesPerUld')::integer then
     raise exception 'A baggage ULD must contain baggage within the configured piece limit' using errcode='23514';
    end if;
    if item->>'uldCode' is distinct from p_planning->>'uldCode' then raise exception 'Use the configured Default Baggage ULD for the baggage proposal' using errcode='23514';end if;
    if (item->>'netWeight')::numeric+(p_planning->'baggageUldLimits'->>'tareWeight')::numeric>(p_planning->'baggageUldLimits'->>'maxGrossWeight')::numeric
      or volume>(p_planning->'baggageUldLimits'->>'maxVolume')::numeric then
     raise exception 'A baggage ULD exceeds its configured maximum gross weight or forecast volume' using errcode='23514';
    end if;
   else bulk_volume:=bulk_volume+volume;bulk_weight:=bulk_weight+(item->>'netWeight')::numeric;end if;
  end loop;
  for forecast in select value from jsonb_array_elements(p_planning->'baggageClasses') loop
   select coalesce(sum((c.value->>'pieces')::numeric),0),coalesce(sum((c.value->>'netWeight')::numeric),0) into pieces,weight
    from jsonb_array_elements(p_values->'contents') i cross join lateral jsonb_array_elements(i.value->'commodities') c
    where c.value->>'classCode'=forecast->>'classCode' and c.value->>'commodityCode'=forecast->>'commodityCode';
   if pieces<>(forecast->>'plannedPieces')::numeric or abs(weight-(forecast->>'plannedWeight')::numeric)>0.5 then
    raise exception 'Reconcile every baggage category with its forecast pieces and net weight' using errcode='23514';
   end if;
  end loop;
  select coalesce(sum((value->>'maximumWeight')::numeric),0),coalesce(sum((value->>'volume')::numeric),0) into max_bulk_weight,max_bulk_volume from jsonb_array_elements(p_planning->'bulkHolds');
  if bulk_weight>max_bulk_weight or bulk_volume>max_bulk_volume then raise exception 'The baggage remainder exceeds the configured Bulk weight or volume capacity' using errcode='23514';end if;
 if uld_count is distinct from (p_values->>'uldCount')::integer or uld_count>(p_planning->>'uldPositionCount')::integer
   or (p_values->>'uldNetWeight') is null or (p_values->>'bulkNetWeight') is null
   or abs(uld_weight-(p_values->>'uldNetWeight')::numeric)>0.5 or abs(bulk_weight-(p_values->>'bulkNetWeight')::numeric)>0.5 then
  raise exception 'Reconcile the baggage ULD count and ULD/Bulk net weights' using errcode='23514';
 end if;
 return jsonb_build_object('uldCount',uld_count,'uldNetWeight',uld_weight,'bulkNetWeight',bulk_weight,'bulkVolume',bulk_volume);
end $$;
revoke all on function private.a350_baggage_contents_summary(jsonb,jsonb) from public,anon,authenticated;

alter function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid)
 rename to get_operational_freight_planning_without_a350_baggage_capacity;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning_without_a350_baggage_capacity(text,uuid) from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".get_operational_freight_planning(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 result jsonb;flight "Basic_Carrier_Record"."Operational_Flights"%rowtype;
 spec record;units record;classes jsonb;targets jsonb:='[]'::jsonb;note text;
 positions integer:=0;candidates jsonb;compatible jsonb;configurations integer;unmapped integer;
 planned integer:=0;reserved integer:=0;saved jsonb;saved_summary jsonb;available integer:=0;carried integer:=0;take integer;row jsonb;
 uld_weight numeric:=0;uld_volume numeric:=0;bulk_weight numeric;bulk_volume numeric;
 bulk_max_weight numeric;bulk_max_volume numeric;bulk_remaining_weight numeric;bulk_remaining_volume numeric;
 space_weight numeric;space_volume numeric;payload numeric;offer numeric;allocations jsonb:='[]'::jsonb;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')) then raise exception 'Load Control access denied' using errcode='42501';end if;
 select * into flight from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 if flight."Aircraft_Type_IATA" is distinct from '359' then
  return "Basic_Carrier_Record".get_operational_freight_planning_without_a350_baggage_capacity(p_iata,p_operational_flight_id);
 end if;
 -- Restore the default-container baseline before the broken pallet exclusion.
 result:="Basic_Carrier_Record".get_operational_freight_planning_without_cargo_uld_allocation(p_iata,p_operational_flight_id);
 if result->>'operatingRole'='FREIGHTER' then
  return "Basic_Carrier_Record".get_operational_freight_planning_without_a350_baggage_capacity(p_iata,p_operational_flight_id);
 end if;
 select btrim(s."ULD_ID") code,btrim(s."ULD_Type") type,s."ULD_Tare_Weight" tare,s."ULD_Max_Weight" gross,
   s."ULD_Baggage_Max_Pieces" pieces,m."ULD_Volume" volume into spec
 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
 left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID")
 where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA"
   and s."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and s."ULD_Baggage_Default";
 select c."Weight_Unit",c."Volume_Unit" into units from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" c
 where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype";
 -- The validated A350 baseline uses kg and m3. Never assume conversion settings.
 if units."Weight_Unit" is distinct from 'KG' or units."Volume_Unit" is distinct from 'M3' then
  note:='A350 baggage planning requires validated KG/M3 configuration';
 elsif spec.code is null or spec.tare is null or spec.tare<0 or spec.gross is null or spec.gross<=spec.tare
   or spec.volume is null or spec.volume<=0 or spec.pieces is null or spec.pieces<=0 then
  note:='Complete the configured Default Baggage ULD and its piece, tare, gross-weight and volume limits';
 end if;
 select coalesce(jsonb_agg(value order by case value->>'commodityCode' when 'BF' then 1 when 'BJ' then 2 when 'BP' then 3 when 'BY' then 4 else 5 end,value->>'classCode'),'[]'::jsonb)
 into classes from jsonb_array_elements(coalesce(result->'baggageClasses','[]'::jsonb));
 if note is null then
  select count(*)::integer,count(distinct p."ULD_Configuration_Code")::integer,
   count(*) filter(where not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" o where o."ULD_Position_UUID"=p."ULD_Position_UUID"))::integer
  into positions,configurations,unmapped from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
  where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype"
    and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Code")=spec.code;
  if positions=0 or configurations<>1 or unmapped>0 then
   note:='Default baggage ULD positions need one complete D3 configuration and every occupancy mapping';
  else
   select jsonb_agg(jsonb_build_object('id',p."ULD_Position_UUID",'bays',
    (select jsonb_agg(p."Hold_Name_ID"||':'||o."Atomic_Bay_ID") from "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" o where o."ULD_Position_UUID"=p."ULD_Position_UUID")) order by p."ULD_Position_UUID")
   into candidates from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
   where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype"
    and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Code")=spec.code;
   compatible:=private.compatible_baggage_positions(candidates);
   positions:=jsonb_array_length(compatible);
  end if;
 end if;
 if note is null then
  begin targets:=private.a350_baggage_piece_targets(classes,spec.pieces,spec.gross-spec.tare,spec.volume);
  exception when check_violation then note:=sqlerrm;end;
  if (select coalesce(sum((value->>'plannedPieces')::integer),0) from jsonb_array_elements(classes)) is distinct from (result->>'plannedBaggagePieces')::integer
    or abs((select coalesce(sum((value->>'plannedWeight')::numeric),0) from jsonb_array_elements(classes))-coalesce((result->>'plannedBaggageWeight')::numeric,0))>0.5 then
   note:='Reconcile the class baggage forecast with the total pieces and net weight';
  end if;
 end if;
 if note is not null then
  return result||jsonb_build_object('ready',false,'missing',coalesce(result->'missing','[]'::jsonb)||jsonb_build_array(note),
   'baggagePlanningNotes',jsonb_build_array(note),'baggageUldPieceTargets','[]'::jsonb,'plannedBaggageUldPositions',0,'uldPositionCount',0,
   'availableUldPositions',0,'cargoUldAllocations','[]'::jsonb,'cargoOfferWeight',null);
 end if;
 planned:=least(positions,jsonb_array_length(targets));reserved:=planned;
 select coalesce(sum(value::integer),0)::integer into carried from jsonb_array_elements(targets) with ordinality t(value,n) where n<=planned;
 for row in select value from jsonb_array_elements(classes) loop
  take:=least(carried,(row->>'plannedPieces')::integer);carried:=carried-take;
  if (row->>'plannedPieces')::integer>0 then
   uld_weight:=uld_weight+round((row->>'plannedWeight')::numeric*take/(row->>'plannedPieces')::integer);
   uld_volume:=uld_volume+(row->>'plannedVolume')::numeric*take/(row->>'plannedPieces')::integer;
  end if;
 end loop;
 bulk_weight:=greatest(0,coalesce((result->>'plannedBaggageWeight')::numeric,0)-uld_weight);
 select greatest(0,coalesce(sum((value->>'plannedVolume')::numeric),0)-uld_volume) into bulk_volume from jsonb_array_elements(classes);
 select coalesce(sum((value->>'maximumWeight')::numeric),0),coalesce(sum((value->>'volume')::numeric),0)
 into bulk_max_weight,bulk_max_volume from jsonb_array_elements(coalesce(result->'bulkHolds','[]'::jsonb));
 if bulk_weight>bulk_max_weight or bulk_volume>bulk_max_volume or (result->>'holdSystem'='ULD' and (bulk_weight>0 or bulk_volume>0)) then
  note:='The proposed baggage remainder exceeds the configured Bulk weight or volume capacity';
 end if;
 -- Forecast proposals and saved accommodation are separate. A valid saved
 -- allocation, including an intentional Bulk override, reserves actual capacity.
 result:=result||jsonb_build_object('uldCode',spec.code,'uldPositionCount',positions,'baggageClasses',classes,
  'baggagePiecesPerUld',spec.pieces,'baggageUldLimits',jsonb_build_object('tareWeight',spec.tare,'maxGrossWeight',spec.gross,'maxVolume',spec.volume));
 select jsonb_build_object('uldCount',a."ULD_Count",'uldNetWeight',a."ULD_Net_Weight",'bulkNetWeight',a."Bulk_Net_Weight",'contents',a."Planned_Contents")
 into saved from "Basic_Carrier_Record"."Operational_Baggage_Accommodation" a where a."Carrier_IATA"=p_iata and a."Operational_Flight_ID"=p_operational_flight_id;
 if saved is not null then
  begin
   saved_summary:=private.a350_baggage_contents_summary(result,saved);
   reserved:=(saved_summary->>'uldCount')::integer;
   bulk_weight:=(saved_summary->>'bulkNetWeight')::numeric;bulk_volume:=(saved_summary->>'bulkVolume')::numeric;note:=null;
  exception when check_violation then note:='Review the saved baggage accommodation: '||sqlerrm;end;
 end if;
 available:=greatest(0,positions-reserved);
 bulk_remaining_volume:=greatest(0,bulk_max_volume-bulk_volume);
 bulk_remaining_weight:=greatest(0,least(bulk_max_weight-bulk_weight,bulk_remaining_volume*(result->>'cargoPlanningDensity')::numeric));
 -- One default-container configuration is the capacity baseline. Pallet alternatives
 -- remain available to the placement solver; their capacities are never added here.
 space_weight:=greatest(0,least(available*(spec.gross-spec.tare)+bulk_remaining_weight,
   (result->>'holdWeightCapacity')::numeric-coalesce((result->>'plannedBaggageWeight')::numeric,0)-reserved*spec.tare));
 space_volume:=available*spec.volume+bulk_remaining_volume;
 payload:=greatest(0,(result->>'remainingPayload')::numeric-reserved*spec.tare);
 offer:=least(payload,space_weight);
 if available>0 then allocations:=jsonb_build_array(jsonb_build_object('kind','CONTAINER','uldType',spec.type,'uldCode',spec.code,'positionCount',available));end if;
 return result||jsonb_build_object('uldCode',spec.code,'primaryUldType',spec.type,'uldPositionCount',positions,
  'baggageClasses',classes,'baggagePiecesPerUld',spec.pieces,'baggageUldPieceTargets',targets,
  'baggageCandidatePositionCount',jsonb_array_length(candidates),'baggageCapacityPositions',compatible,
  'baggageUldLimits',jsonb_build_object('tareWeight',spec.tare,'maxGrossWeight',spec.gross,'maxVolume',spec.volume),
  'plannedBaggageUldPositions',planned,'availableUldPositions',available,'cargoUldAllocations',allocations,
  'baggageCapacityBasis','DEFAULT_CONTAINER_CONFIGURATION','baggagePlanningNotes','[]'::jsonb,
  'baggageCapacityReservation',jsonb_build_object('source',case when saved is null then 'FORECAST_PROPOSAL' else 'SAVED_ACCOMMODATION' end,'uldCount',reserved),
  'baggageAccommodationNotes',case when saved is not null and note is not null then jsonb_build_array(note) else '[]'::jsonb end,
  'baggageProposalNotes',case when saved is null and note is not null then jsonb_build_array(note) else '[]'::jsonb end,
  'ready',coalesce((result->>'ready')::boolean,false) and note is null,
  'missing',coalesce(result->'missing','[]'::jsonb)||case when note is null then '[]'::jsonb else jsonb_build_array(note) end,
  'availableBulkWeight',round(bulk_remaining_weight),'availableBulkVolume',round(bulk_remaining_volume,4),'availableBulkVolumeUnit','M3',
  'spaceWeightCapacity',space_weight,'remainingHoldWeight',space_weight,'remainingHoldVolume',round(space_volume,2),
  'remainingPayload',payload,'totalAvailableCargoVolume',round(space_volume,2),'cargoOfferWeight',case when note is null then offer else null end,
  'limitingFactor',case when offer=payload then 'PAYLOAD' else 'HOLD_WEIGHT' end);
end $$;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;

alter function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb)
 rename to save_operational_baggage_accommodation_without_a350_limits;
revoke all on function "Basic_Carrier_Record".save_operational_baggage_accommodation_without_a350_limits(text,uuid,integer,jsonb) from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".save_operational_baggage_accommodation(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare planning jsonb;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE')) then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if exists(select 1 from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id and "Aircraft_Type_IATA"='359') then
  planning:="Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);
  if jsonb_array_length(coalesce(planning->'baggagePlanningNotes','[]'::jsonb))>0 then raise exception '%',planning->'baggagePlanningNotes'->>0 using errcode='23514';end if;
  perform private.a350_baggage_contents_summary(planning,p_values);
 end if;
 -- Existing validation, optimistic version check and persistence remain authoritative.
 return "Basic_Carrier_Record".save_operational_baggage_accommodation_without_a350_limits(p_iata,p_operational_flight_id,p_expected_version,p_values);
end $$;
revoke all on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
