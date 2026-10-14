begin;
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
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
