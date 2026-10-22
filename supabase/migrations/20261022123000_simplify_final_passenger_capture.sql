begin;

alter function "Basic_Carrier_Record".get_operational_final_traffic(text,uuid)
  rename to get_operational_final_traffic_category_split;
alter function "Basic_Carrier_Record".save_operational_final_traffic(text,uuid,integer,boolean,jsonb)
  rename to save_operational_final_traffic_category_split;

create function "Basic_Carrier_Record".get_operational_final_traffic(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 legacy jsonb; item jsonb; classes jsonb:='[]'::jsonb; areas jsonb:='[]'::jsonb;
 totals jsonb:=jsonb_build_object('male',0,'female',0,'child',0,'infant',0);
 passenger_weight numeric:=0; unit text; flight "Basic_Carrier_Record"."Operational_Flights"%rowtype;
 male_weight numeric; female_weight numeric; child_weight numeric; infant_weight numeric;
begin
 legacy:="Basic_Carrier_Record".get_operational_final_traffic_category_split(upper(btrim(p_iata)),p_operational_flight_id);
 if not coalesce((legacy->>'applicable')::boolean,false) then
  return legacy||jsonb_build_object('passengerCounts',totals);
 end if;
 for item in select value from jsonb_array_elements(legacy->'classes') loop
  totals:=jsonb_build_object(
   'male',(totals->>'male')::integer+coalesce((item->>'male')::integer,0),
   'female',(totals->>'female')::integer+coalesce((item->>'female')::integer,0),
   'child',(totals->>'child')::integer+coalesce((item->>'child')::integer,0),
   'infant',(totals->>'infant')::integer+coalesce((item->>'infant')::integer,0));
  classes:=classes||jsonb_build_array(jsonb_build_object(
   'code',item->>'code','name',item->>'name','booked',(item->>'booked')::integer,
   'final',coalesce((item->>'male')::integer,0)+coalesce((item->>'female')::integer,0)+coalesce((item->>'child')::integer,0)));
 end loop;
 for item in select value from jsonb_array_elements(legacy->'areas') loop
  areas:=areas||jsonb_build_array(jsonb_build_object(
   'areaId',item->>'areaId','seats',(item->>'seats')::integer,
   'passengers',coalesce((item->>'male')::integer,0)+coalesce((item->>'female')::integer,0)+coalesce((item->>'child')::integer,0)));
 end loop;
 select * into flight from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=upper(btrim(p_iata)) and "Operational_Flight_ID"=p_operational_flight_id;
 select case when "Carrier_Unit_Weight_LB" and not "Carrier_Unit_Weight_KG" then 'LB' else 'KG' end into unit from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=upper(btrim(p_iata));
 select
  round((coalesce(q.male,q.adult,(q.male+q.female)/2)+case when q.includes_hand then 0 else coalesce(q.hand_weight,0) end)*case when unit='LB' then 0.45359237 else 1 end,2),
  round((coalesce(q.female,q.adult,(q.male+q.female)/2)+case when q.includes_hand then 0 else coalesce(q.hand_weight,0) end)*case when unit='LB' then 0.45359237 else 1 end,2),
  case when q.child is null then null else round((q.child+case when q.includes_hand then 0 else coalesce(q.hand_weight,0) end)*case when unit='LB' then 0.45359237 else 1 end,2) end,
  case when q.infant is null then null else round((q.infant+case when q.includes_hand then 0 else coalesce(q.hand_weight,0) end)*case when unit='LB' then 0.45359237 else 1 end,2) end
 into male_weight,female_weight,child_weight,infant_weight from(
  select w."Adult"::numeric adult,w."Male"::numeric male,w."Female"::numeric female,w."Child"::numeric child,w."Infant"::numeric infant,w."Passenger_Weights_Include_Handbaggage" includes_hand,w."Hand_Baggage_Weight"::numeric hand_weight,1 priority
  from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w where flight."Passenger_Weight_Basis"='VARIATION' and w."Carrier_IATA"=upper(btrim(p_iata)) and w."Class_Code" is null and w."Flight_Type_Variation"=flight."Passenger_Flight_Variation"
  union all
  select w."Adult",w."Male",w."Female",w."Child",w."Infant",w."Passenger_Weights_Include_Handbaggage",w."Hand_Baggage_Weight",9
  from "Basic_Carrier_Record"."Carrier_Passenger_Weights_ALLFLIGHTS" w where w."Carrier_IATA"=upper(btrim(p_iata))
  order by priority limit 1
 )q;
 if male_weight is null and female_weight is null and child_weight is null and infant_weight is null then
  passenger_weight:=coalesce((legacy->>'passengerWeight')::numeric,0);
 else
  passenger_weight:=coalesce((totals->>'male')::integer,0)*coalesce(male_weight,0)+coalesce((totals->>'female')::integer,0)*coalesce(female_weight,0)+coalesce((totals->>'child')::integer,0)*coalesce(child_weight,0)+coalesce((totals->>'infant')::integer,0)*coalesce(infant_weight,0);
 end if;
 return legacy||jsonb_build_object('passengerCounts',totals,'classes',classes,'areas',areas,'totalPassengers',(totals->>'male')::integer+(totals->>'female')::integer+(totals->>'child')::integer+(totals->>'infant')::integer,'passengerWeight',round(passenger_weight,2));
end $$;

create function "Basic_Carrier_Record".save_operational_final_traffic(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_finalise boolean,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 item jsonb; counts jsonb:=p_values->'passengerCounts'; legacy_classes jsonb:='[]'::jsonb; legacy_areas jsonb:='[]'::jsonb;
 rem_male integer; rem_female integer; rem_child integer; infants integer; row_total integer; row_male integer; row_female integer; row_child integer;
 class_total integer:=0; area_total integer:=0; seated integer; first_row boolean:=true; legacy_values jsonb;
begin
 if jsonb_typeof(counts) is distinct from 'object' or jsonb_typeof(p_values->'classes') is distinct from 'array' or jsonb_typeof(p_values->'areas') is distinct from 'array' then raise exception 'Enter the final passenger figures' using errcode='22023';end if;
 if coalesce(counts->>'male','')!~'^[0-9]{1,3}$' or coalesce(counts->>'female','')!~'^[0-9]{1,3}$' or coalesce(counts->>'child','')!~'^[0-9]{1,3}$' or coalesce(counts->>'infant','')!~'^[0-9]{1,3}$' then raise exception 'Check the final passenger categories' using errcode='22023';end if;
 rem_male:=(counts->>'male')::integer;rem_female:=(counts->>'female')::integer;rem_child:=(counts->>'child')::integer;infants:=(counts->>'infant')::integer;seated:=rem_male+rem_female+rem_child;
 for item in select value from jsonb_array_elements(p_values->'classes') loop
  if coalesce(item->>'code','')!~'^[A-Z]$' or coalesce(item->>'final','')!~'^[0-9]{1,3}$' then raise exception 'Check the final passengers by class' using errcode='22023';end if;
  row_total:=(item->>'final')::integer;class_total:=class_total+row_total;row_male:=least(rem_male,row_total);rem_male:=rem_male-row_male;row_total:=row_total-row_male;row_female:=least(rem_female,row_total);rem_female:=rem_female-row_female;row_total:=row_total-row_female;row_child:=least(rem_child,row_total);rem_child:=rem_child-row_child;
  legacy_classes:=legacy_classes||jsonb_build_array(jsonb_build_object('code',item->>'code','male',row_male,'female',row_female,'child',row_child,'infant',case when first_row then infants else 0 end));first_row:=false;
 end loop;
 if class_total<>seated or rem_male<>0 or rem_female<>0 or rem_child<>0 then raise exception 'Reconcile the final passengers by class with Male, Female and Child' using errcode='23514';end if;
 rem_male:=(counts->>'male')::integer;rem_female:=(counts->>'female')::integer;rem_child:=(counts->>'child')::integer;first_row:=true;
 for item in select value from jsonb_array_elements(p_values->'areas') loop
  if coalesce(item->>'areaId','')='' or coalesce(item->>'seats','')!~'^[0-9]{1,3}$' or coalesce(item->>'passengers','')!~'^[0-9]{1,3}$' or (item->>'passengers')::integer>(item->>'seats')::integer then raise exception 'Check the final cabin-area distribution' using errcode='23514';end if;
  row_total:=(item->>'passengers')::integer;area_total:=area_total+row_total;row_male:=least(rem_male,row_total);rem_male:=rem_male-row_male;row_total:=row_total-row_male;row_female:=least(rem_female,row_total);rem_female:=rem_female-row_female;row_total:=row_total-row_female;row_child:=least(rem_child,row_total);rem_child:=rem_child-row_child;
  legacy_areas:=legacy_areas||jsonb_build_array(jsonb_build_object('areaId',item->>'areaId','seats',(item->>'seats')::integer,'male',row_male,'female',row_female,'child',row_child,'infant',case when first_row then infants else 0 end));first_row:=false;
 end loop;
 if area_total<>seated or rem_male<>0 or rem_female<>0 or rem_child<>0 then raise exception 'Reconcile the cabin-area distribution with the final seated passenger total' using errcode='23514';end if;
 legacy_values:=jsonb_set(jsonb_set(p_values,'{classes}',legacy_classes),'{areas}',legacy_areas)-'passengerCounts';
 perform "Basic_Carrier_Record".save_operational_final_traffic_category_split(upper(btrim(p_iata)),p_operational_flight_id,p_expected_version,p_finalise,legacy_values);
 return "Basic_Carrier_Record".get_operational_final_traffic(upper(btrim(p_iata)),p_operational_flight_id);
end $$;

revoke all on function "Basic_Carrier_Record".get_operational_final_traffic_category_split(text,uuid) from public,anon,authenticated;
revoke all on function "Basic_Carrier_Record".save_operational_final_traffic_category_split(text,uuid,integer,boolean,jsonb) from public,anon,authenticated;
revoke all on function "Basic_Carrier_Record".get_operational_final_traffic(text,uuid) from public,anon;
revoke all on function "Basic_Carrier_Record".save_operational_final_traffic(text,uuid,integer,boolean,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_final_traffic(text,uuid) to authenticated;
grant execute on function "Basic_Carrier_Record".save_operational_final_traffic(text,uuid,integer,boolean,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
