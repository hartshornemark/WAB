begin;

create or replace function "Basic_Carrier_Record".save_operational_baggage_accommodation(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 planning jsonb;current_version integer;uld_count integer;uld_weight numeric;bulk_weight numeric;total_weight numeric;total_pieces integer;hold_system text;max_uld integer;piece_capacity integer;contents jsonb;item jsonb;item_kind text;item_id text;item_pieces integer;item_weight numeric;commodity_rows jsonb;commodity jsonb;commodity_pieces integer;commodity_weight numeric;commodity_piece_total integer;commodity_weight_total numeric;uld_rows integer:=0;bulk_rows integer:=0;content_pieces integer:=0;content_uld_weight numeric:=0;content_bulk_weight numeric:=0;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE')) then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'contents')<>'array' then raise exception 'Check the baggage accommodation and planned contents' using errcode='22023';end if;
 begin uld_count:=(p_values->>'uldCount')::integer;uld_weight:=(p_values->>'uldNetWeight')::numeric;bulk_weight:=(p_values->>'bulkNetWeight')::numeric;contents:=p_values->'contents';exception when others then raise exception 'Enter valid baggage accommodation values' using errcode='22023';end;
 planning:="Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);
 if planning->>'operatingRole'='FREIGHTER' then raise exception 'Baggage accommodation is available for passenger aircraft' using errcode='23514';end if;
 total_weight:=coalesce(nullif(planning->>'plannedBaggageWeight','')::numeric,0);total_pieces:=nullif(planning->>'plannedBaggagePieces','')::integer;hold_system:=planning->>'holdSystem';max_uld:=coalesce(nullif(planning->>'uldPositionCount','')::integer,0);piece_capacity:=nullif(planning->>'baggagePiecesPerUld','')::integer;
 if uld_count<0 or uld_count>max_uld or uld_weight<0 or bulk_weight<0 or abs((uld_weight+bulk_weight)-total_weight)>0.5 then raise exception 'Allocate the complete planned baggage weight between ULD and Bulk accommodation' using errcode='23514';end if;
 if (uld_count=0 and uld_weight>0) or (uld_count>0 and uld_weight<=0) then raise exception 'The baggage ULD count and ULD baggage weight must agree' using errcode='23514';end if;
 if hold_system='ULD' and bulk_weight>0 then raise exception 'This aircraft has no Bulk baggage accommodation' using errcode='23514';end if;
 for item in select value from jsonb_array_elements(contents) loop
  begin item_kind:=upper(item->>'kind');item_id:=btrim(item->>'loadId');item_pieces:=(item->>'pieces')::integer;item_weight:=(item->>'netWeight')::numeric;exception when others then raise exception 'Check each planned baggage-content row' using errcode='22023';end;
  if item_kind not in('ULD','BULK') or item_pieces<0 or item_weight<0 then raise exception 'Check each planned baggage-content row' using errcode='23514';end if;
  commodity_rows:=item->'commodities';
  if jsonb_typeof(commodity_rows)<>'array' or jsonb_array_length(commodity_rows)=0 then commodity_rows:=jsonb_build_array(jsonb_build_object('classCode',item->>'classCode','commodityCode',coalesce(item->>'commodityCode','B'),'pieces',item_pieces,'netWeight',item_weight));end if;
  if jsonb_array_length(commodity_rows)>4 then raise exception 'A baggage load may contain no more than four baggage commodities' using errcode='23514';end if;
  commodity_piece_total:=0;commodity_weight_total:=0;
  for commodity in select value from jsonb_array_elements(commodity_rows) loop
   begin commodity_pieces:=(commodity->>'pieces')::integer;commodity_weight:=(commodity->>'netWeight')::numeric;exception when others then raise exception 'Check each baggage commodity within the load' using errcode='22023';end;
   if commodity_pieces<0 or commodity_weight<0 or (nullif(commodity->>'classCode','') is not null and upper(commodity->>'classCode')!~'^[A-Z]$') or upper(coalesce(commodity->>'commodityCode','')) not in('B','BF','BJ','BP','BY') then raise exception 'Check each baggage commodity within the load' using errcode='23514';end if;
   commodity_piece_total:=commodity_piece_total+commodity_pieces;commodity_weight_total:=commodity_weight_total+commodity_weight;
  end loop;
  if (select count(*) from jsonb_array_elements(commodity_rows))<>(select count(distinct upper(coalesce(value->>'classCode',''))||':'||upper(coalesce(value->>'commodityCode',''))) from jsonb_array_elements(commodity_rows)) or commodity_piece_total<>item_pieces or abs(commodity_weight_total-item_weight)>0.5 then raise exception 'Reconcile each load commodity breakdown with its pieces and net weight' using errcode='23514';end if;
  if item_kind='ULD' then if item_id!~'^PLANNED_BAGGAGE:[0-9]+$' then raise exception 'Check each planned baggage ULD' using errcode='23514';end if;if piece_capacity is not null and item_pieces>piece_capacity then raise exception 'A baggage ULD exceeds the configured piece capacity' using errcode='23514';end if;uld_rows:=uld_rows+1;content_uld_weight:=content_uld_weight+item_weight;
  else if item_id<>'PLANNED_BAGGAGE:BULK' then raise exception 'Check the planned Bulk baggage load' using errcode='23514';end if;bulk_rows:=bulk_rows+1;content_bulk_weight:=content_bulk_weight+item_weight;end if;
  content_pieces:=content_pieces+item_pieces;
 end loop;
 if (select count(*) from jsonb_array_elements(contents))<>(select count(distinct value->>'loadId') from jsonb_array_elements(contents)) then raise exception 'Each planned baggage load must be unique' using errcode='23514';end if;
 if uld_rows<>uld_count or bulk_rows>1 then raise exception 'The planned baggage contents must match the selected ULD count and may include one Bulk location' using errcode='23514';end if;
 if abs(content_uld_weight-uld_weight)>0.5 or abs(content_bulk_weight-bulk_weight)>0.5 then raise exception 'Reconcile the planned baggage-content weights' using errcode='23514';end if;
 if total_pieces is not null and content_pieces<>total_pieces then raise exception 'Allocate every planned baggage piece before accepting the baggage plan' using errcode='23514';end if;
 select "Version" into current_version from "Basic_Carrier_Record"."Operational_Baggage_Accommodation" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if coalesce(current_version,0)<>p_expected_version then raise exception 'The baggage accommodation changed. Reload before saving.' using errcode='40001';end if;
 insert into "Basic_Carrier_Record"."Operational_Baggage_Accommodation"("Carrier_IATA","Operational_Flight_ID","Version","ULD_Count","ULD_Net_Weight","Bulk_Net_Weight","Planned_Contents","Accepted_By") values(p_iata,p_operational_flight_id,coalesce(current_version,0)+1,uld_count,uld_weight,bulk_weight,contents,(select auth.uid())) on conflict("Carrier_IATA","Operational_Flight_ID") do update set "Version"=excluded."Version","ULD_Count"=excluded."ULD_Count","ULD_Net_Weight"=excluded."ULD_Net_Weight","Bulk_Net_Weight"=excluded."Bulk_Net_Weight","Planned_Contents"=excluded."Planned_Contents","Accepted_At"=now(),"Accepted_By"=excluded."Accepted_By";
 return "Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata,p_operational_flight_id);
end $$;

create or replace function "Basic_Carrier_Record".save_operational_final_traffic(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_finalise boolean,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 current_version integer:=0;accommodation jsonb;final_by_class jsonb:='{}'::jsonb;item jsonb;contents jsonb;areas jsonb;bag_pieces integer;bag_weight numeric;uld_count integer;class_male integer:=0;class_female integer:=0;class_child integer:=0;class_infant integer:=0;area_male integer:=0;area_female integer:=0;area_child integer:=0;area_infant integer:=0;item_kind text;item_id text;item_pieces integer;item_weight numeric;commodity_rows jsonb;commodity jsonb;commodity_pieces integer;commodity_weight numeric;commodity_piece_total integer;commodity_weight_total numeric;content_pieces integer:=0;content_weight numeric:=0;uld_rows integer:=0;bulk_rows integer:=0;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE')) then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if jsonb_typeof(p_values->'classes') is distinct from 'array' or jsonb_typeof(p_values->'areas') is distinct from 'array' or jsonb_typeof(p_values->'contents') is distinct from 'array' then raise exception 'Enter the final passenger and baggage figures' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_values->'classes') loop if (item->>'code')!~'^[A-Z]$' or coalesce(item->>'male','')!~'^[0-9]{1,3}$' or coalesce(item->>'female','')!~'^[0-9]{1,3}$' or coalesce(item->>'child','')!~'^[0-9]{1,3}$' or coalesce(item->>'infant','')!~'^[0-9]{1,3}$' then raise exception 'Check the final passenger figures' using errcode='22023';end if;final_by_class:=final_by_class||jsonb_build_object(item->>'code',jsonb_build_object('male',(item->>'male')::integer,'female',(item->>'female')::integer,'child',(item->>'child')::integer,'infant',(item->>'infant')::integer));class_male:=class_male+(item->>'male')::integer;class_female:=class_female+(item->>'female')::integer;class_child:=class_child+(item->>'child')::integer;class_infant:=class_infant+(item->>'infant')::integer;end loop;
 areas:=p_values->'areas';
 for item in select value from jsonb_array_elements(areas) loop if coalesce(item->>'areaId','')='' or coalesce(item->>'seats','')!~'^[0-9]{1,3}$' or coalesce(item->>'male','')!~'^[0-9]{1,3}$' or coalesce(item->>'female','')!~'^[0-9]{1,3}$' or coalesce(item->>'child','')!~'^[0-9]{1,3}$' or coalesce(item->>'infant','')!~'^[0-9]{1,3}$' or (item->>'male')::integer+(item->>'female')::integer+(item->>'child')::integer>(item->>'seats')::integer then raise exception 'Check the final cabin-area distribution' using errcode='23514';end if;area_male:=area_male+(item->>'male')::integer;area_female:=area_female+(item->>'female')::integer;area_child:=area_child+(item->>'child')::integer;area_infant:=area_infant+(item->>'infant')::integer;end loop;
 if class_male<>area_male or class_female<>area_female or class_child<>area_child or class_infant<>area_infant then raise exception 'Reconcile the passenger totals with the cabin-area distribution' using errcode='23514';end if;
 begin bag_pieces:=(p_values->>'baggagePieces')::integer;bag_weight:=(p_values->>'baggageNetWeight')::numeric;exception when others then raise exception 'Check the final baggage figures' using errcode='22023';end;if bag_pieces<0 or bag_weight<0 then raise exception 'Check the final baggage figures' using errcode='23514';end if;contents:=p_values->'contents';
 for item in select value from jsonb_array_elements(contents) loop
  begin item_kind:=upper(item->>'kind');item_id:=btrim(item->>'loadId');item_pieces:=(item->>'pieces')::integer;item_weight:=(item->>'netWeight')::numeric;exception when others then raise exception 'Check each final baggage-content row' using errcode='22023';end;
  if item_kind not in('ULD','BULK') or item_pieces<0 or item_weight<0 then raise exception 'Check each final baggage-content row' using errcode='23514';end if;
  commodity_rows:=item->'commodities';
  if jsonb_typeof(commodity_rows)<>'array' or jsonb_array_length(commodity_rows)=0 then commodity_rows:=jsonb_build_array(jsonb_build_object('classCode',item->>'classCode','commodityCode',coalesce(item->>'commodityCode','B'),'pieces',item_pieces,'netWeight',item_weight));end if;
  if jsonb_array_length(commodity_rows)>4 then raise exception 'A baggage load may contain no more than four baggage commodities' using errcode='23514';end if;
  commodity_piece_total:=0;commodity_weight_total:=0;
  for commodity in select value from jsonb_array_elements(commodity_rows) loop
   begin commodity_pieces:=(commodity->>'pieces')::integer;commodity_weight:=(commodity->>'netWeight')::numeric;exception when others then raise exception 'Check each baggage commodity within the load' using errcode='22023';end;
   if commodity_pieces<0 or commodity_weight<0 or (nullif(commodity->>'classCode','') is not null and upper(commodity->>'classCode')!~'^[A-Z]$') or upper(coalesce(commodity->>'commodityCode','')) not in('B','BF','BJ','BP','BY') then raise exception 'Check each baggage commodity within the load' using errcode='23514';end if;
   commodity_piece_total:=commodity_piece_total+commodity_pieces;commodity_weight_total:=commodity_weight_total+commodity_weight;
  end loop;
  if (select count(*) from jsonb_array_elements(commodity_rows))<>(select count(distinct upper(coalesce(value->>'classCode',''))||':'||upper(coalesce(value->>'commodityCode',''))) from jsonb_array_elements(commodity_rows)) or commodity_piece_total<>item_pieces or abs(commodity_weight_total-item_weight)>0.5 then raise exception 'Reconcile each load commodity breakdown with its pieces and net weight' using errcode='23514';end if;
  if item_kind='ULD' then if item_id!~'^PLANNED_BAGGAGE:[0-9]+$' then raise exception 'Check each final baggage ULD' using errcode='23514';end if;if p_finalise and coalesce(btrim(item->>'uldNumber'),'')='' then raise exception 'Enter the actual number of every baggage ULD before finalising' using errcode='23514';end if;uld_rows:=uld_rows+1;
  else if item_id<>'PLANNED_BAGGAGE:BULK' then raise exception 'Check the final Bulk baggage load' using errcode='23514';end if;bulk_rows:=bulk_rows+1;end if;
  content_pieces:=content_pieces+item_pieces;content_weight:=content_weight+item_weight;
 end loop;
 if (select count(*) from jsonb_array_elements(contents))<>(select count(distinct value->>'loadId') from jsonb_array_elements(contents)) then raise exception 'Each baggage-content load must be unique' using errcode='23514';end if;
 accommodation:="Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata,p_operational_flight_id);uld_count:=coalesce((accommodation->>'uldCount')::integer,0);
 if uld_rows<>uld_count or bulk_rows>1 then raise exception 'The baggage contents must retain the accepted ULD count and may include one Bulk location' using errcode='23514';end if;
 if p_finalise and (content_pieces<>bag_pieces or content_weight<>bag_weight or (select count(distinct content_row->>'uldNumber') from jsonb_array_elements(contents) content_row where content_row->>'kind'='ULD')<>uld_count) then raise exception 'Reconcile and number every baggage ULD before finalising' using errcode='23514';end if;
 select "Version" into current_version from "Basic_Carrier_Record"."Operational_Final_Traffic" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;current_version:=coalesce(current_version,0);if current_version<>p_expected_version then raise exception 'The final traffic figures changed. Reload before saving.' using errcode='40001';end if;
 insert into "Basic_Carrier_Record"."Operational_Final_Traffic"("Carrier_IATA","Operational_Flight_ID","Version","Status","Final_By_Class","Passenger_Areas","Baggage_Pieces","Baggage_Net_Weight","Baggage_Contents","Updated_By","Updated_At","Finalised_At") values(p_iata,p_operational_flight_id,current_version+1,case when p_finalise then 'BAGGAGE_FINAL' else 'TRAFFIC_FINAL' end,final_by_class,areas,bag_pieces,bag_weight,contents,(select auth.uid()),now(),case when p_finalise then now() else null end) on conflict("Carrier_IATA","Operational_Flight_ID") do update set "Version"=excluded."Version","Status"=excluded."Status","Final_By_Class"=excluded."Final_By_Class","Passenger_Areas"=excluded."Passenger_Areas","Baggage_Pieces"=excluded."Baggage_Pieces","Baggage_Net_Weight"=excluded."Baggage_Net_Weight","Baggage_Contents"=excluded."Baggage_Contents","Updated_By"=excluded."Updated_By","Updated_At"=excluded."Updated_At","Finalised_At"=excluded."Finalised_At";
 return "Basic_Carrier_Record".get_operational_final_traffic(p_iata,p_operational_flight_id);
end $$;

revoke all on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".save_operational_final_traffic(text,uuid,integer,boolean,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".save_operational_final_traffic(text,uuid,integer,boolean,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
