begin;

alter table "Basic_Carrier_Record"."Carrier_Planning_Assumptions"
 add column if not exists "Baggage_Commodity_Code" varchar(2);

alter table "Basic_Carrier_Record"."Carrier_Planning_Assumptions"
 drop constraint if exists "carrier_planning_assumptions_baggage_commodity_code_check";
alter table "Basic_Carrier_Record"."Carrier_Planning_Assumptions"
 add constraint "carrier_planning_assumptions_baggage_commodity_code_check"
 check ("Baggage_Commodity_Code" is null or "Baggage_Commodity_Code" in ('B','BF','BJ','BP','BY'));

alter function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid)
 rename to get_operational_freight_planning_without_baggage_classes;

create or replace function "Basic_Carrier_Record".get_operational_freight_planning(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 result jsonb;
 flight "Basic_Carrier_Record"."Operational_Flights"%rowtype;
 passenger jsonb;
 passenger_class jsonb;
 assumption record;
 baggage_classes jsonb:='[]'::jsonb;
 class_code text;
 class_name text;
 commodity_code text;
 booked integer;
 class_pieces integer;
 class_weight numeric;
 class_volume numeric;
 total_weight numeric;
 total_volume numeric;
 piece_capacity integer;
 planned_uld_count integer:=0;
 class_piece_total integer:=0;
 maximum_uld_count integer;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')) then raise exception 'Load Control access denied' using errcode='42501';end if;
 result:="Basic_Carrier_Record".get_operational_freight_planning_without_baggage_classes(p_iata,p_operational_flight_id);
 if result->>'operatingRole'='FREIGHTER' then return result||jsonb_build_object('baggageClasses','[]'::jsonb);end if;
 select * into flight from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 passenger:="Basic_Carrier_Record".get_operational_passenger_booking(p_iata,p_operational_flight_id);
 total_weight:=coalesce(nullif(result->>'plannedBaggageWeight','')::numeric,0);
 total_volume:=nullif(result->>'plannedBaggageVolume','')::numeric;
 piece_capacity:=nullif(result->>'baggagePiecesPerUld','')::integer;
 maximum_uld_count:=coalesce(nullif(result->>'uldPositionCount','')::integer,0);
 for passenger_class in select value from jsonb_array_elements(coalesce(passenger->'classes','[]'::jsonb)) loop
  class_code:=upper(btrim(passenger_class->>'code'));
  class_name:=btrim(coalesce(passenger_class->>'name',''));
  booked:=coalesce((passenger_class->>'booked')::integer,0);
  select q.* into assumption from(
   select p.*,1 priority from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where p."Carrier_IATA"=p_iata and p."Class_Code"=class_code and ((flight."Baggage_Weight_Basis"='VARIATION' and p."Flight_Type_Variation"=flight."Baggage_Flight_Variation") or (flight."Baggage_Weight_Basis"<>'VARIATION' and p."Flight_Type_Variation" is null))
   union all select p.*,2 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where flight."Baggage_Weight_Basis"='VARIATION' and p."Carrier_IATA"=p_iata and p."Class_Code" is null and p."Flight_Type_Variation"=flight."Baggage_Flight_Variation"
   union all select p.*,3 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where flight."Baggage_Weight_Basis"='VARIATION' and p."Carrier_IATA"=p_iata and p."Class_Code"=class_code and p."Flight_Type_Variation" is null
   union all select p.*,9 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where p."Carrier_IATA"=p_iata and p."Class_Code" is null and p."Flight_Type_Variation" is null order by priority limit 1
  )q;
  if not found then continue;end if;
  class_pieces:=round(booked*coalesce(assumption."Average_Bags_Per_Passenger",0))::integer;
  class_weight:=round(booked*coalesce(assumption."Average_Bag_Weight_Per_Passenger",0));
  class_volume:=case when assumption."Average_Bag_Volume" is not null then round(class_pieces*assumption."Average_Bag_Volume",4) when total_volume is not null and total_weight>0 then round(total_volume*class_weight/total_weight,4) else null end;
  commodity_code:=coalesce(assumption."Baggage_Commodity_Code",case when upper(class_name) like '%FIRST%' or class_code='F' then 'BF' when upper(class_name) like '%PREMIUM%' or class_code in('W','P') then 'BP' when upper(class_name) like '%BUSINESS%' or class_code in('C','J') then 'BJ' when upper(class_name) like '%ECONOMY%' or class_code='Y' then 'BY' else 'B' end);
  baggage_classes:=baggage_classes||jsonb_build_array(jsonb_build_object('classCode',class_code,'className',class_name,'commodityCode',commodity_code,'passengers',booked,'bagsPerPassenger',assumption."Average_Bags_Per_Passenger",'plannedPieces',class_pieces,'weightPerPassenger',assumption."Average_Bag_Weight_Per_Passenger",'plannedWeight',class_weight,'plannedVolume',class_volume));
  class_piece_total:=class_piece_total+class_pieces;
 end loop;
 if piece_capacity is not null and piece_capacity>0 and class_piece_total>0 then planned_uld_count:=ceil(class_piece_total::numeric/piece_capacity)::integer;else planned_uld_count:=coalesce(nullif(result->>'plannedBaggageUldPositions','')::integer,0);end if;
 planned_uld_count:=least(planned_uld_count,maximum_uld_count);
 return result||jsonb_build_object('baggageClasses',baggage_classes,'plannedBaggageUldPositions',planned_uld_count,'availableUldPositions',greatest(0,maximum_uld_count-planned_uld_count));
end $$;

create or replace function "Basic_Carrier_Record".save_operational_baggage_accommodation(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare planning jsonb;current_version integer;uld_count integer;uld_weight numeric;bulk_weight numeric;total_weight numeric;total_pieces integer;hold_system text;max_uld integer;piece_capacity integer;contents jsonb;item jsonb;item_kind text;item_id text;item_pieces integer;item_weight numeric;class_code text;commodity_code text;uld_rows integer:=0;bulk_rows integer:=0;content_pieces integer:=0;content_uld_weight numeric:=0;content_bulk_weight numeric:=0;
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
  begin item_kind:=upper(item->>'kind');item_id:=btrim(item->>'loadId');item_pieces:=(item->>'pieces')::integer;item_weight:=(item->>'netWeight')::numeric;class_code:=nullif(upper(btrim(item->>'classCode')),'');commodity_code:=upper(btrim(coalesce(item->>'commodityCode','B')));exception when others then raise exception 'Check each planned baggage-content row' using errcode='22023';end;
  if item_kind not in('ULD','BULK') or item_pieces<0 or item_weight<0 or (class_code is not null and class_code!~'^[A-Z]$') or commodity_code not in('B','BF','BJ','BP','BY') then raise exception 'Check each planned baggage-content row' using errcode='23514';end if;
  if item_kind='ULD' then if item_id!~'^PLANNED_BAGGAGE:[0-9]+$' then raise exception 'Check each planned baggage ULD' using errcode='23514';end if;if piece_capacity is not null and item_pieces>piece_capacity then raise exception 'A baggage ULD exceeds the configured piece capacity' using errcode='23514';end if;uld_rows:=uld_rows+1;content_uld_weight:=content_uld_weight+item_weight;
  else if item_id<>'PLANNED_BAGGAGE:BULK' and item_id!~'^PLANNED_BAGGAGE:([A-Z]|B[A-Z]?):BULK$' then raise exception 'Check the planned Bulk baggage load' using errcode='23514';end if;bulk_rows:=bulk_rows+1;content_bulk_weight:=content_bulk_weight+item_weight;end if;
  content_pieces:=content_pieces+item_pieces;
 end loop;
 if (select count(*) from jsonb_array_elements(contents))<>(select count(distinct value->>'loadId') from jsonb_array_elements(contents)) then raise exception 'Each planned baggage load must be unique' using errcode='23514';end if;
 if uld_rows<>uld_count or bulk_rows>4 then raise exception 'The planned baggage contents must match the selected ULD count and may include one Bulk remainder per class' using errcode='23514';end if;
 if abs(content_uld_weight-uld_weight)>0.5 or abs(content_bulk_weight-bulk_weight)>0.5 then raise exception 'Reconcile the planned baggage-content weights' using errcode='23514';end if;
 if total_pieces is not null and content_pieces<>total_pieces then raise exception 'Allocate every planned baggage piece before accepting the baggage plan' using errcode='23514';end if;
 select "Version" into current_version from "Basic_Carrier_Record"."Operational_Baggage_Accommodation" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if coalesce(current_version,0)<>p_expected_version then raise exception 'The baggage accommodation changed. Reload before saving.' using errcode='40001';end if;
 insert into "Basic_Carrier_Record"."Operational_Baggage_Accommodation"("Carrier_IATA","Operational_Flight_ID","Version","ULD_Count","ULD_Net_Weight","Bulk_Net_Weight","Planned_Contents","Accepted_By") values(p_iata,p_operational_flight_id,coalesce(current_version,0)+1,uld_count,uld_weight,bulk_weight,contents,(select auth.uid())) on conflict("Carrier_IATA","Operational_Flight_ID") do update set "Version"=excluded."Version","ULD_Count"=excluded."ULD_Count","ULD_Net_Weight"=excluded."ULD_Net_Weight","Bulk_Net_Weight"=excluded."Bulk_Net_Weight","Planned_Contents"=excluded."Planned_Contents","Accepted_At"=now(),"Accepted_By"=excluded."Accepted_By";
 return "Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata,p_operational_flight_id);
end $$;

create or replace function "Basic_Carrier_Record".save_operational_final_traffic(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_finalise boolean,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare current_version integer:=0;accommodation jsonb;final_by_class jsonb:='{}'::jsonb;item jsonb;contents jsonb;areas jsonb;bag_pieces integer;bag_weight numeric;uld_count integer;class_male integer:=0;class_female integer:=0;class_child integer:=0;class_infant integer:=0;area_male integer:=0;area_female integer:=0;area_child integer:=0;area_infant integer:=0;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE')) then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if jsonb_typeof(p_values->'classes') is distinct from 'array' or jsonb_typeof(p_values->'areas') is distinct from 'array' or jsonb_typeof(p_values->'contents') is distinct from 'array' then raise exception 'Enter the final passenger and baggage figures' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_values->'classes') loop if (item->>'code')!~'^[A-Z]$' or coalesce(item->>'male','')!~'^[0-9]{1,3}$' or coalesce(item->>'female','')!~'^[0-9]{1,3}$' or coalesce(item->>'child','')!~'^[0-9]{1,3}$' or coalesce(item->>'infant','')!~'^[0-9]{1,3}$' then raise exception 'Check the final passenger figures' using errcode='22023';end if;final_by_class:=final_by_class||jsonb_build_object(item->>'code',jsonb_build_object('male',(item->>'male')::integer,'female',(item->>'female')::integer,'child',(item->>'child')::integer,'infant',(item->>'infant')::integer));class_male:=class_male+(item->>'male')::integer;class_female:=class_female+(item->>'female')::integer;class_child:=class_child+(item->>'child')::integer;class_infant:=class_infant+(item->>'infant')::integer;end loop;
 areas:=p_values->'areas';
 for item in select value from jsonb_array_elements(areas) loop if coalesce(item->>'areaId','')='' or coalesce(item->>'seats','')!~'^[0-9]{1,3}$' or coalesce(item->>'male','')!~'^[0-9]{1,3}$' or coalesce(item->>'female','')!~'^[0-9]{1,3}$' or coalesce(item->>'child','')!~'^[0-9]{1,3}$' or coalesce(item->>'infant','')!~'^[0-9]{1,3}$' or (item->>'male')::integer+(item->>'female')::integer+(item->>'child')::integer>(item->>'seats')::integer then raise exception 'Check the final cabin-area distribution' using errcode='23514';end if;area_male:=area_male+(item->>'male')::integer;area_female:=area_female+(item->>'female')::integer;area_child:=area_child+(item->>'child')::integer;area_infant:=area_infant+(item->>'infant')::integer;end loop;
 if class_male<>area_male or class_female<>area_female or class_child<>area_child or class_infant<>area_infant then raise exception 'Reconcile the passenger totals with the cabin-area distribution' using errcode='23514';end if;
 begin bag_pieces:=(p_values->>'baggagePieces')::integer;bag_weight:=(p_values->>'baggageNetWeight')::numeric;exception when others then raise exception 'Check the final baggage figures' using errcode='22023';end;if bag_pieces<0 or bag_weight<0 then raise exception 'Check the final baggage figures' using errcode='23514';end if;contents:=p_values->'contents';
 if exists(select 1 from jsonb_array_elements(contents) c where c->>'kind' not in('ULD','BULK') or coalesce(c->>'commodityCode','B') not in('B','BF','BJ','BP','BY') or (nullif(c->>'classCode','') is not null and (c->>'classCode')!~'^[A-Z]$')) then raise exception 'Check the baggage-content class and commodity codes' using errcode='23514';end if;
 if (select count(*) from jsonb_array_elements(contents))<>(select count(distinct value->>'loadId') from jsonb_array_elements(contents)) then raise exception 'Each baggage-content load must be unique' using errcode='23514';end if;
 accommodation:="Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata,p_operational_flight_id);uld_count:=coalesce((accommodation->>'uldCount')::integer,0);
 if (select count(*) from jsonb_array_elements(contents) content_row where content_row->>'kind'='ULD')<>uld_count or (select count(*) from jsonb_array_elements(contents) content_row where content_row->>'kind'='BULK')>4 then raise exception 'The baggage contents must retain the accepted ULD count and may include one final Bulk remainder per class' using errcode='23514';end if;
 if p_finalise and ((select coalesce(sum((content_row->>'pieces')::integer),0) from jsonb_array_elements(contents) content_row)<>bag_pieces or (select coalesce(sum((content_row->>'netWeight')::numeric),0) from jsonb_array_elements(contents) content_row)<>bag_weight or exists(select 1 from jsonb_array_elements(contents) content_row where content_row->>'kind'='ULD' and coalesce(btrim(content_row->>'uldNumber'),'')='') or (select count(distinct content_row->>'uldNumber') from jsonb_array_elements(contents) content_row where content_row->>'kind'='ULD')<>uld_count) then raise exception 'Reconcile and number every baggage ULD before finalising' using errcode='23514';end if;
 select "Version" into current_version from "Basic_Carrier_Record"."Operational_Final_Traffic" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;current_version:=coalesce(current_version,0);if current_version<>p_expected_version then raise exception 'The final traffic figures changed. Reload before saving.' using errcode='40001';end if;
 insert into "Basic_Carrier_Record"."Operational_Final_Traffic"("Carrier_IATA","Operational_Flight_ID","Version","Status","Final_By_Class","Passenger_Areas","Baggage_Pieces","Baggage_Net_Weight","Baggage_Contents","Updated_By","Updated_At","Finalised_At") values(p_iata,p_operational_flight_id,current_version+1,case when p_finalise then 'BAGGAGE_FINAL' else 'TRAFFIC_FINAL' end,final_by_class,areas,bag_pieces,bag_weight,contents,(select auth.uid()),now(),case when p_finalise then now() else null end) on conflict("Carrier_IATA","Operational_Flight_ID") do update set "Version"=excluded."Version","Status"=excluded."Status","Final_By_Class"=excluded."Final_By_Class","Passenger_Areas"=excluded."Passenger_Areas","Baggage_Pieces"=excluded."Baggage_Pieces","Baggage_Net_Weight"=excluded."Baggage_Net_Weight","Baggage_Contents"=excluded."Baggage_Contents","Updated_By"=excluded."Updated_By","Updated_At"=excluded."Updated_At","Finalised_At"=excluded."Finalised_At";
 return "Basic_Carrier_Record".get_operational_final_traffic(p_iata,p_operational_flight_id);
end $$;

revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
revoke all on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".save_operational_final_traffic(text,uuid,integer,boolean,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;
grant execute on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".save_operational_final_traffic(text,uuid,integer,boolean,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
