begin;
create or replace function "Basic_Carrier_Record".get_operational_freight_planning(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; f "Basic_Carrier_Record"."Operational_Flights"%rowtype; passenger jsonb; pax jsonb; assumption record; booked integer; pieces numeric:=0; complete boolean:=true; uld_volume numeric; baggage_volume numeric; piece_capacity integer;
begin
 p_iata:=upper(btrim(p_iata));
 result:="Basic_Carrier_Record".get_operational_freight_planning_without_baggage_pieces(p_iata,p_operational_flight_id);
 if result->>'operatingRole'='FREIGHTER' then return result;end if;
 select * into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 passenger:="Basic_Carrier_Record".get_operational_passenger_booking(p_iata,p_operational_flight_id);
 for pax in select value from jsonb_array_elements(coalesce(passenger->'classes','[]'::jsonb)) loop
  booked:=coalesce((pax->>'booked')::integer,0);
  select q.* into assumption from(
   select p.*,1 priority from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where p."Carrier_IATA"=p_iata and p."Class_Code"=pax->>'code' and ((f."Baggage_Weight_Basis"='VARIATION' and p."Flight_Type_Variation"=f."Baggage_Flight_Variation") or (f."Baggage_Weight_Basis"<>'VARIATION' and p."Flight_Type_Variation" is null))
   union all select p.*,2 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where f."Baggage_Weight_Basis"='VARIATION' and p."Carrier_IATA"=p_iata and p."Class_Code" is null and p."Flight_Type_Variation"=f."Baggage_Flight_Variation"
   union all select p.*,3 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where f."Baggage_Weight_Basis"='VARIATION' and p."Carrier_IATA"=p_iata and p."Class_Code"=pax->>'code' and p."Flight_Type_Variation" is null
   union all select p.*,9 from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where p."Carrier_IATA"=p_iata and p."Class_Code" is null and p."Flight_Type_Variation" is null order by priority limit 1
  )q;
  if assumption is null or assumption."Average_Bags_Per_Passenger" is null then complete:=false;else pieces:=pieces+booked*assumption."Average_Bags_Per_Passenger";end if;
 end loop;
 baggage_volume:=nullif(result->>'plannedBaggageVolume','')::numeric;
 select m."ULD_Volume" into uld_volume from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID") where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=f."Aircraft_Type_IATA" and s."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and btrim(s."ULD_ID")=btrim(result->>'uldCode') limit 1;
 if complete and pieces>0 and baggage_volume>0 and uld_volume>0 then piece_capacity:=floor(uld_volume/(baggage_volume/pieces));end if;
 return result||jsonb_build_object('plannedBaggagePieces',case when complete then round(pieces)::integer else null end,'baggagePieceBasis',case when f."Baggage_Weight_Basis"='ACTUAL' then 'ACTUAL' else 'STANDARD' end,'baggagePiecesPerUld',piece_capacity);
end $$;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
