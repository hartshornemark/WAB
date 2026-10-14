begin;

create table "Basic_Carrier_Record"."Operational_Final_Traffic"(
  "Carrier_IATA" text not null,
  "Operational_Flight_ID" uuid not null references "Basic_Carrier_Record"."Operational_Flights"("Operational_Flight_ID") on delete cascade,
  "Version" integer not null default 1 check("Version">0),
  "Status" text not null check("Status" in('TRAFFIC_FINAL','BAGGAGE_FINAL')),
  "Final_By_Class" jsonb not null check(jsonb_typeof("Final_By_Class")='object'),
  "Passenger_Areas" jsonb not null check(jsonb_typeof("Passenger_Areas")='array'),
  "Baggage_Pieces" integer not null check("Baggage_Pieces">=0),
  "Baggage_Net_Weight" numeric not null check("Baggage_Net_Weight">=0),
  "Baggage_Contents" jsonb not null check(jsonb_typeof("Baggage_Contents")='array'),
  "Updated_By" uuid not null default auth.uid(),
  "Updated_At" timestamptz not null default now(),
  "Finalised_At" timestamptz,
  primary key("Carrier_IATA","Operational_Flight_ID")
);
alter table "Basic_Carrier_Record"."Operational_Final_Traffic" enable row level security;
revoke all on table "Basic_Carrier_Record"."Operational_Final_Traffic" from public,anon,authenticated;
create policy "operational_final_traffic_select" on "Basic_Carrier_Record"."Operational_Final_Traffic" for select to authenticated using(
 private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')
);

create or replace function "Basic_Carrier_Record".get_operational_final_traffic(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare booking jsonb; planning jsonb; accommodation jsonb; saved "Basic_Carrier_Record"."Operational_Final_Traffic"%rowtype; flight "Basic_Carrier_Record"."Operational_Flights"%rowtype; item jsonb; counts jsonb; classes jsonb:='[]'::jsonb; contents jsonb:='[]'::jsonb; areas jsonb:='[]'::jsonb; total_pax integer:=0; passenger_weight numeric:=0; uld_count integer; bag_pieces integer; bag_weight numeric; piece_capacity integer; remaining_pieces integer; remaining_weight integer; row_pieces integer; row_weight integer; content_index integer; uld_code text; bulk_planned numeric; total_planned numeric; unit text; male_weight numeric; female_weight numeric; child_weight numeric; infant_weight numeric;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')) then raise exception 'Load Control access denied' using errcode='42501';end if;
 booking:="Basic_Carrier_Record".get_operational_passenger_booking(p_iata,p_operational_flight_id);
 if not coalesce((booking->>'applicable')::boolean,false) then return jsonb_build_object('applicable',false,'canEdit',booking->'canEdit','version',0,'status','EMPTY','classes','[]'::jsonb,'areas','[]'::jsonb,'totalPassengers',0,'passengerWeight',0,'baggagePieces',0,'baggageNetWeight',0,'contents','[]'::jsonb,'updatedAt',null,'finalisedAt',null);end if;
 select * into flight from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 select case when "Carrier_Unit_Weight_LB" and not "Carrier_Unit_Weight_KG" then 'LB' else 'KG' end into unit from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata;
 planning:="Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);accommodation:="Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata,p_operational_flight_id);
 select * into saved from "Basic_Carrier_Record"."Operational_Final_Traffic" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 for item in select value from jsonb_array_elements(booking->'classes') loop
  counts:=saved."Final_By_Class"->(item->>'code');
  if jsonb_typeof(counts) is distinct from 'object' then counts:=jsonb_build_object('male',ceil(coalesce((item->>'booked')::numeric,0)/2)::integer,'female',floor(coalesce((item->>'booked')::numeric,0)/2)::integer,'child',0,'infant',0);end if;
  select round((coalesce(q.male,q.adult,(q.male+q.female)/2)+case when q.includes_hand then 0 else coalesce(q.hand_weight,0) end)*case when unit='LB' then 0.45359237 else 1 end,2),round((coalesce(q.female,q.adult,(q.male+q.female)/2)+case when q.includes_hand then 0 else coalesce(q.hand_weight,0) end)*case when unit='LB' then 0.45359237 else 1 end,2),case when q.child is null then null else round((q.child+case when q.includes_hand then 0 else coalesce(q.hand_weight,0) end)*case when unit='LB' then 0.45359237 else 1 end,2) end,case when q.infant is null then null else round((q.infant+case when q.includes_hand then 0 else coalesce(q.hand_weight,0) end)*case when unit='LB' then 0.45359237 else 1 end,2) end into male_weight,female_weight,child_weight,infant_weight from(
   select w."Adult"::numeric adult,w."Male"::numeric male,w."Female"::numeric female,w."Child"::numeric child,w."Infant"::numeric infant,w."Passenger_Weights_Include_Handbaggage" includes_hand,w."Hand_Baggage_Weight"::numeric hand_weight,1 priority from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w where w."Carrier_IATA"=p_iata and w."Class_Code"=item->>'code' and ((flight."Passenger_Weight_Basis"='VARIATION' and w."Flight_Type_Variation"=flight."Passenger_Flight_Variation") or (flight."Passenger_Weight_Basis"<>'VARIATION' and w."Flight_Type_Variation" is null))
   union all select w."Adult",w."Male",w."Female",w."Child",w."Infant",w."Passenger_Weights_Include_Handbaggage",w."Hand_Baggage_Weight",2 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w where flight."Passenger_Weight_Basis"='VARIATION' and w."Carrier_IATA"=p_iata and w."Class_Code" is null and w."Flight_Type_Variation"=flight."Passenger_Flight_Variation"
   union all select w."Adult",w."Male",w."Female",w."Child",w."Infant",w."Passenger_Weights_Include_Handbaggage",w."Hand_Baggage_Weight",3 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w where flight."Passenger_Weight_Basis"='VARIATION' and w."Carrier_IATA"=p_iata and w."Class_Code"=item->>'code' and w."Flight_Type_Variation" is null
   union all select w."Adult",w."Male",w."Female",w."Child",w."Infant",w."Passenger_Weights_Include_Handbaggage",w."Hand_Baggage_Weight",9 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_ALLFLIGHTS" w where w."Carrier_IATA"=p_iata order by priority limit 1
  )q;
  total_pax:=total_pax+coalesce((counts->>'male')::integer,0)+coalesce((counts->>'female')::integer,0)+coalesce((counts->>'child')::integer,0)+coalesce((counts->>'infant')::integer,0);
  passenger_weight:=passenger_weight+coalesce((counts->>'male')::integer,0)*coalesce(male_weight,0)+coalesce((counts->>'female')::integer,0)*coalesce(female_weight,0)+coalesce((counts->>'child')::integer,0)*coalesce(child_weight,0)+coalesce((counts->>'infant')::integer,0)*coalesce(infant_weight,0);
  classes:=classes||jsonb_build_array(jsonb_build_object('code',item->>'code','name',item->>'name','booked',(item->>'booked')::integer,'male',coalesce((counts->>'male')::integer,0),'female',coalesce((counts->>'female')::integer,0),'child',coalesce((counts->>'child')::integer,0),'infant',coalesce((counts->>'infant')::integer,0),'final',coalesce((counts->>'male')::integer,0)+coalesce((counts->>'female')::integer,0)+coalesce((counts->>'child')::integer,0)+coalesce((counts->>'infant')::integer,0),'planningWeight',item->'planningWeight','passengerWeight',round(coalesce((counts->>'male')::integer,0)*coalesce(male_weight,0)+coalesce((counts->>'female')::integer,0)*coalesce(female_weight,0)+coalesce((counts->>'child')::integer,0)*coalesce(child_weight,0)+coalesce((counts->>'infant')::integer,0)*coalesce(infant_weight,0),2),'maleWeight',male_weight,'femaleWeight',female_weight,'childWeight',child_weight,'infantWeight',infant_weight));
 end loop;
 bag_pieces:=coalesce(saved."Baggage_Pieces",(planning->>'plannedBaggagePieces')::integer,0);bag_weight:=coalesce(saved."Baggage_Net_Weight",(planning->>'plannedBaggageWeight')::numeric,0);areas:=coalesce(saved."Passenger_Areas",'[]'::jsonb);
 if saved."Operational_Flight_ID" is not null then contents:=saved."Baggage_Contents";else
  uld_count:=coalesce((accommodation->>'uldCount')::integer,0);uld_code:=planning->>'uldCode';piece_capacity:=nullif((planning->>'baggagePiecesPerUld')::integer,0);bulk_planned:=coalesce((accommodation->>'bulkNetWeight')::numeric,0);total_planned:=coalesce((accommodation->>'totalNetWeight')::numeric,0);
  remaining_pieces:=bag_pieces-case when total_planned>0 then round(bag_pieces*bulk_planned/total_planned)::integer else 0 end;remaining_weight:=round(bag_weight-case when total_planned>0 then bag_weight*bulk_planned/total_planned else 0 end)::integer;
  for content_index in 1..uld_count loop row_pieces:=case when content_index=uld_count then remaining_pieces when piece_capacity is not null then least(piece_capacity,remaining_pieces) else floor(remaining_pieces::numeric/(uld_count-content_index+1))::integer end;row_weight:=case when content_index=uld_count then remaining_weight when remaining_pieces>0 then round(remaining_weight*row_pieces::numeric/remaining_pieces)::integer else 0 end;remaining_pieces:=remaining_pieces-row_pieces;remaining_weight:=remaining_weight-row_weight;contents:=contents||jsonb_build_array(jsonb_build_object('loadId','PLANNED_BAGGAGE:'||content_index,'kind','ULD','uldCode',uld_code,'uldNumber',null,'pieces',row_pieces,'netWeight',row_weight));end loop;
  if bulk_planned>0 then contents:=contents||jsonb_build_array(jsonb_build_object('loadId','PLANNED_BAGGAGE:BULK','kind','BULK','uldCode',null,'uldNumber',null,'pieces',bag_pieces-coalesce((select sum((value->>'pieces')::integer) from jsonb_array_elements(contents)),0),'netWeight',round(bag_weight-coalesce((select sum((value->>'netWeight')::numeric) from jsonb_array_elements(contents)),0))));end if;
 end if;
 return jsonb_build_object('applicable',true,'canEdit',booking->'canEdit','version',coalesce(saved."Version",0),'status',coalesce(saved."Status",'EMPTY'),'classes',classes,'areas',areas,'totalPassengers',total_pax,'passengerWeight',round(passenger_weight,2),'baggagePieces',bag_pieces,'baggageNetWeight',round(bag_weight),'contents',contents,'updatedAt',saved."Updated_At",'finalisedAt',saved."Finalised_At");
end $$;

create or replace function "Basic_Carrier_Record".save_operational_final_traffic(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_finalise boolean,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare current_version integer:=0; accommodation jsonb; final_by_class jsonb:='{}'::jsonb; item jsonb; contents jsonb; areas jsonb; bag_pieces integer; bag_weight numeric; uld_count integer; class_male integer:=0;class_female integer:=0;class_child integer:=0;class_infant integer:=0;area_male integer:=0;area_female integer:=0;area_child integer:=0;area_infant integer:=0;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE')) then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if jsonb_typeof(p_values->'classes') is distinct from 'array' or jsonb_typeof(p_values->'areas') is distinct from 'array' or jsonb_typeof(p_values->'contents') is distinct from 'array' then raise exception 'Enter the final passenger and baggage figures' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_values->'classes') loop
  if (item->>'code')!~'^[A-Z]$' or coalesce(item->>'male','')!~'^[0-9]{1,3}$' or coalesce(item->>'female','')!~'^[0-9]{1,3}$' or coalesce(item->>'child','')!~'^[0-9]{1,3}$' or coalesce(item->>'infant','')!~'^[0-9]{1,3}$' then raise exception 'Check the final passenger figures' using errcode='22023';end if;
  final_by_class:=final_by_class||jsonb_build_object(item->>'code',jsonb_build_object('male',(item->>'male')::integer,'female',(item->>'female')::integer,'child',(item->>'child')::integer,'infant',(item->>'infant')::integer));class_male:=class_male+(item->>'male')::integer;class_female:=class_female+(item->>'female')::integer;class_child:=class_child+(item->>'child')::integer;class_infant:=class_infant+(item->>'infant')::integer;
 end loop;
 areas:=p_values->'areas';
 for item in select value from jsonb_array_elements(areas) loop
  if coalesce(item->>'areaId','')='' or coalesce(item->>'seats','')!~'^[0-9]{1,3}$' or coalesce(item->>'male','')!~'^[0-9]{1,3}$' or coalesce(item->>'female','')!~'^[0-9]{1,3}$' or coalesce(item->>'child','')!~'^[0-9]{1,3}$' or coalesce(item->>'infant','')!~'^[0-9]{1,3}$' or (item->>'male')::integer+(item->>'female')::integer+(item->>'child')::integer>(item->>'seats')::integer then raise exception 'Check the final cabin-area distribution' using errcode='23514';end if;
  area_male:=area_male+(item->>'male')::integer;area_female:=area_female+(item->>'female')::integer;area_child:=area_child+(item->>'child')::integer;area_infant:=area_infant+(item->>'infant')::integer;
 end loop;
 if class_male<>area_male or class_female<>area_female or class_child<>area_child or class_infant<>area_infant then raise exception 'Reconcile the passenger totals with the cabin-area distribution' using errcode='23514';end if;
 begin bag_pieces:=(p_values->>'baggagePieces')::integer;bag_weight:=(p_values->>'baggageNetWeight')::numeric;exception when others then raise exception 'Check the final baggage figures' using errcode='22023';end;if bag_pieces<0 or bag_weight<0 then raise exception 'Check the final baggage figures' using errcode='23514';end if;contents:=p_values->'contents';
 accommodation:="Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata,p_operational_flight_id);uld_count:=coalesce((accommodation->>'uldCount')::integer,0);
 if (select count(*) from jsonb_array_elements(contents) content_row where content_row->>'kind'='ULD')<>uld_count or (select count(*) from jsonb_array_elements(contents) content_row where content_row->>'kind'='BULK')>1 then raise exception 'The baggage contents must retain the accepted ULD count and may include one final Bulk baggage load' using errcode='23514';end if;
 if p_finalise and ((select coalesce(sum((content_row->>'pieces')::integer),0) from jsonb_array_elements(contents) content_row)<>bag_pieces or (select coalesce(sum((content_row->>'netWeight')::numeric),0) from jsonb_array_elements(contents) content_row)<>bag_weight or exists(select 1 from jsonb_array_elements(contents) content_row where content_row->>'kind'='ULD' and coalesce(btrim(content_row->>'uldNumber'),'')='') or (select count(distinct content_row->>'uldNumber') from jsonb_array_elements(contents) content_row where content_row->>'kind'='ULD')<>uld_count) then raise exception 'Reconcile and number every baggage ULD before finalising' using errcode='23514';end if;
 select "Version" into current_version from "Basic_Carrier_Record"."Operational_Final_Traffic" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;current_version:=coalesce(current_version,0);if current_version<>p_expected_version then raise exception 'The final traffic figures changed. Reload before saving.' using errcode='40001';end if;
 insert into "Basic_Carrier_Record"."Operational_Final_Traffic"("Carrier_IATA","Operational_Flight_ID","Version","Status","Final_By_Class","Passenger_Areas","Baggage_Pieces","Baggage_Net_Weight","Baggage_Contents","Updated_By","Updated_At","Finalised_At") values(p_iata,p_operational_flight_id,current_version+1,case when p_finalise then 'BAGGAGE_FINAL' else 'TRAFFIC_FINAL' end,final_by_class,areas,bag_pieces,bag_weight,contents,(select auth.uid()),now(),case when p_finalise then now() else null end)
 on conflict("Carrier_IATA","Operational_Flight_ID") do update set "Version"=excluded."Version","Status"=excluded."Status","Final_By_Class"=excluded."Final_By_Class","Passenger_Areas"=excluded."Passenger_Areas","Baggage_Pieces"=excluded."Baggage_Pieces","Baggage_Net_Weight"=excluded."Baggage_Net_Weight","Baggage_Contents"=excluded."Baggage_Contents","Updated_By"=excluded."Updated_By","Updated_At"=excluded."Updated_At","Finalised_At"=excluded."Finalised_At";
 return "Basic_Carrier_Record".get_operational_final_traffic(p_iata,p_operational_flight_id);
end $$;

revoke all on function "Basic_Carrier_Record".get_operational_final_traffic(text,uuid) from public,anon;
revoke all on function "Basic_Carrier_Record".save_operational_final_traffic(text,uuid,integer,boolean,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_final_traffic(text,uuid) to authenticated;
grant execute on function "Basic_Carrier_Record".save_operational_final_traffic(text,uuid,integer,boolean,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
