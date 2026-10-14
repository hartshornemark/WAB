begin;

alter table "Basic_Carrier_Record"."Operational_Baggage_Accommodation"
  add column if not exists "Planned_Contents" jsonb not null default '[]'::jsonb
  check (jsonb_typeof("Planned_Contents")='array');

create or replace function "Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 planning jsonb;
 saved "Basic_Carrier_Record"."Operational_Baggage_Accommodation"%rowtype;
 has_saved boolean;
 contents jsonb:='[]'::jsonb;
 uld_count integer;
 uld_weight numeric;
 bulk_weight numeric;
 total_weight numeric;
 total_pieces integer;
 bulk_pieces integer;
 remaining_pieces integer;
 remaining_weight numeric;
 piece_capacity integer;
 row_pieces integer;
 row_weight numeric;
 index integer;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')) then raise exception 'Load Control access denied' using errcode='42501';end if;
 planning:="Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);
 if planning->>'operatingRole'='FREIGHTER' then return null;end if;
 select * into saved from "Basic_Carrier_Record"."Operational_Baggage_Accommodation" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 has_saved:=found;
 uld_count:=case when has_saved then saved."ULD_Count" else coalesce(nullif(planning->>'plannedBaggageUldPositions','')::integer,0) end;
 uld_weight:=case when has_saved then saved."ULD_Net_Weight" else coalesce(nullif(planning->>'plannedBaggageWeight','')::numeric,0) end;
 bulk_weight:=case when has_saved then saved."Bulk_Net_Weight" else 0 end;
 total_weight:=coalesce(nullif(planning->>'plannedBaggageWeight','')::numeric,0);
 total_pieces:=coalesce(nullif(planning->>'plannedBaggagePieces','')::integer,0);
 piece_capacity:=nullif(planning->>'baggagePiecesPerUld','')::integer;
 if has_saved and jsonb_array_length(saved."Planned_Contents")>0 then
  contents:=saved."Planned_Contents";
 else
  bulk_pieces:=case when uld_count=0 then total_pieces when total_weight>0 then round(total_pieces*bulk_weight/total_weight)::integer else 0 end;
  remaining_pieces:=greatest(0,total_pieces-bulk_pieces);
  remaining_weight:=greatest(0,uld_weight);
  if uld_count>0 then
   for index in 1..uld_count loop
    row_pieces:=case when index=uld_count then remaining_pieces when piece_capacity is null then floor(remaining_pieces::numeric/(uld_count-index+1))::integer else least(piece_capacity,remaining_pieces) end;
    row_weight:=case when index=uld_count then remaining_weight when greatest(0,total_pieces-bulk_pieces)>0 then round(uld_weight*row_pieces/greatest(1,total_pieces-bulk_pieces)) else floor(uld_weight/uld_count) end;
    contents:=contents||jsonb_build_array(jsonb_build_object('loadId','PLANNED_BAGGAGE:'||index,'kind','ULD','uldCode',planning->>'uldCode','uldNumber',null,'pieces',row_pieces,'netWeight',row_weight));
    remaining_pieces:=remaining_pieces-row_pieces;
    remaining_weight:=remaining_weight-row_weight;
   end loop;
  end if;
  if bulk_weight>0 or planning->>'holdSystem'='BULK' then
   contents:=contents||jsonb_build_array(jsonb_build_object('loadId','PLANNED_BAGGAGE:BULK','kind','BULK','uldCode',null,'uldNumber',null,'pieces',bulk_pieces,'netWeight',bulk_weight));
  end if;
 end if;
 return jsonb_build_object(
  'status',case when has_saved then 'ACCEPTED' else 'PROPOSED' end,
  'version',case when has_saved then saved."Version" else 0 end,
  'uldCount',uld_count,
  'uldNetWeight',uld_weight,
  'bulkNetWeight',bulk_weight,
  'totalNetWeight',total_weight,
  'uldCode',planning->>'uldCode',
  'maximumUldCount',coalesce(nullif(planning->>'uldPositionCount','')::integer,0),
  'holdSystem',planning->>'holdSystem',
  'contents',contents
 );
end $$;
revoke all on function "Basic_Carrier_Record".get_operational_baggage_accommodation(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_baggage_accommodation(text,uuid) to authenticated;

create or replace function "Basic_Carrier_Record".save_operational_baggage_accommodation(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 planning jsonb;
 current_version integer;
 uld_count integer;
 uld_weight numeric;
 bulk_weight numeric;
 total_weight numeric;
 total_pieces integer;
 hold_system text;
 max_uld integer;
 piece_capacity integer;
 contents jsonb;
 item jsonb;
 item_kind text;
 item_id text;
 item_pieces integer;
 item_weight numeric;
 uld_rows integer:=0;
 bulk_rows integer:=0;
 content_pieces integer:=0;
 content_uld_weight numeric:=0;
 content_bulk_weight numeric:=0;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE')) then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'contents')<>'array' then raise exception 'Check the baggage accommodation and planned contents' using errcode='22023';end if;
 begin
  uld_count:=(p_values->>'uldCount')::integer;
  uld_weight:=(p_values->>'uldNetWeight')::numeric;
  bulk_weight:=(p_values->>'bulkNetWeight')::numeric;
  contents:=p_values->'contents';
 exception when others then raise exception 'Enter valid baggage accommodation values' using errcode='22023';end;
 planning:="Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);
 if planning->>'operatingRole'='FREIGHTER' then raise exception 'Baggage accommodation is available for passenger aircraft' using errcode='23514';end if;
 total_weight:=coalesce(nullif(planning->>'plannedBaggageWeight','')::numeric,0);
 total_pieces:=nullif(planning->>'plannedBaggagePieces','')::integer;
 hold_system:=planning->>'holdSystem';
 max_uld:=coalesce(nullif(planning->>'uldPositionCount','')::integer,0);
 piece_capacity:=nullif(planning->>'baggagePiecesPerUld','')::integer;
 if uld_count<0 or uld_count>max_uld or uld_weight<0 or bulk_weight<0 or abs((uld_weight+bulk_weight)-total_weight)>0.5 then raise exception 'Allocate the complete planned baggage weight between ULD and Bulk accommodation' using errcode='23514';end if;
 if (uld_count=0 and uld_weight>0) or (uld_count>0 and uld_weight<=0) then raise exception 'The baggage ULD count and ULD baggage weight must agree' using errcode='23514';end if;
 if hold_system='ULD' and bulk_weight>0 then raise exception 'This aircraft has no Bulk baggage accommodation' using errcode='23514';end if;
 for item in select value from jsonb_array_elements(contents) loop
  begin item_kind:=upper(item->>'kind');item_id:=btrim(item->>'loadId');item_pieces:=(item->>'pieces')::integer;item_weight:=(item->>'netWeight')::numeric;exception when others then raise exception 'Check each planned baggage-content row' using errcode='22023';end;
  if item_kind not in('ULD','BULK') or item_pieces<0 or item_weight<0 then raise exception 'Check each planned baggage-content row' using errcode='23514';end if;
  if item_kind='ULD' then
   if item_id!~'^PLANNED_BAGGAGE:[0-9]+$' then raise exception 'Check each planned baggage ULD' using errcode='23514';end if;
   if piece_capacity is not null and item_pieces>piece_capacity then raise exception 'A baggage ULD exceeds the configured piece capacity' using errcode='23514';end if;
   uld_rows:=uld_rows+1;content_uld_weight:=content_uld_weight+item_weight;
  else
   if item_id<>'PLANNED_BAGGAGE:BULK' then raise exception 'Check the planned Bulk baggage load' using errcode='23514';end if;
   bulk_rows:=bulk_rows+1;content_bulk_weight:=content_bulk_weight+item_weight;
  end if;
  content_pieces:=content_pieces+item_pieces;
 end loop;
 if (select count(*) from jsonb_array_elements(contents))<>(select count(distinct value->>'loadId') from jsonb_array_elements(contents)) then raise exception 'Each planned baggage load must be unique' using errcode='23514';end if;
 if uld_rows<>uld_count or bulk_rows>1 then raise exception 'The planned baggage contents must match the selected ULD and Bulk accommodation' using errcode='23514';end if;
 if abs(content_uld_weight-uld_weight)>0.5 or abs(content_bulk_weight-bulk_weight)>0.5 then raise exception 'Reconcile the planned baggage-content weights' using errcode='23514';end if;
 if total_pieces is not null and content_pieces<>total_pieces then raise exception 'Allocate every planned baggage piece before accepting the baggage plan' using errcode='23514';end if;
 select "Version" into current_version from "Basic_Carrier_Record"."Operational_Baggage_Accommodation" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if coalesce(current_version,0)<>p_expected_version then raise exception 'The baggage accommodation changed. Reload before saving.' using errcode='40001';end if;
 insert into "Basic_Carrier_Record"."Operational_Baggage_Accommodation"("Carrier_IATA","Operational_Flight_ID","Version","ULD_Count","ULD_Net_Weight","Bulk_Net_Weight","Planned_Contents","Accepted_By") values(p_iata,p_operational_flight_id,coalesce(current_version,0)+1,uld_count,uld_weight,bulk_weight,contents,(select auth.uid()))
 on conflict("Carrier_IATA","Operational_Flight_ID") do update set "Version"=excluded."Version","ULD_Count"=excluded."ULD_Count","ULD_Net_Weight"=excluded."ULD_Net_Weight","Bulk_Net_Weight"=excluded."Bulk_Net_Weight","Planned_Contents"=excluded."Planned_Contents","Accepted_At"=now(),"Accepted_By"=excluded."Accepted_By";
 return "Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata,p_operational_flight_id);
end $$;
revoke all on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
