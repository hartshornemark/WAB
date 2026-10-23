-- MASTER_ULD_List stores ULD_Volume as double precision. Convert it explicitly
-- when calling the exact-numeric baggage limit helper. No flight data changes.
begin;
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
  begin targets:=private.a350_baggage_piece_targets(classes,spec.pieces,spec.gross-spec.tare,spec.volume::numeric);
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

notify pgrst,'reload schema';
commit;
