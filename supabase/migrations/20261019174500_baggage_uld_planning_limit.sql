begin;

alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications" add column if not exists "ULD_Baggage_Max_Pieces" integer;
alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications" drop constraint if exists carrier_uld_baggage_max_pieces_check;
alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications" add constraint carrier_uld_baggage_max_pieces_check check("ULD_Baggage_Max_Pieces" between 1 and 999);

with calculated as(
 select s."Carrier_IATA",s."Aircraft_Type_IATA",s."Aircraft_Series_Subtype",s."ULD_ID",greatest(1,floor((m."ULD_Volume"/case when c."Volume_Unit"='FT3' then 0.028316846592 else 1 end)*u."Density_Checked_Baggage"/coalesce(nullif(w.maximum_bag_weight,0),15))::integer) pieces
 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
 join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID")
 join "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" c on c."Carrier_IATA"=s."Carrier_IATA" and c."Aircraft_Type_IATA"=s."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=s."Aircraft_Series_Subtype"
 join "Basic_Carrier_Record"."Carrier_Units_of_Measure" u on u."Carrier_IATA"=s."Carrier_IATA"
 left join lateral(select max(p."Average_Bag_Weight_Per_Passenger") maximum_bag_weight from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where p."Carrier_IATA"=s."Carrier_IATA" and p."Average_Bag_Weight_Per_Passenger">0)w on true
 where s."ULD_Baggage_Default"
)
update "Basic_Carrier_Record"."Carrier_ULD_Specifications" s set "ULD_Baggage_Max_Pieces"=least(999,coalesce(c.pieces,40)) from calculated c where s."Carrier_IATA"=c."Carrier_IATA" and s."Aircraft_Type_IATA"=c."Aircraft_Type_IATA" and s."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype" and s."ULD_ID"=c."ULD_ID";

create or replace function "Basic_Carrier_Record".get_carrier_ulds(p_iata text,p_type text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;records_inventory boolean;rows jsonb;
begin
 result:="Basic_Carrier_Record".get_carrier_ulds_without_inventory_flag(p_iata,p_type,p_subtype);
 select coalesce(s."Records_ULD_Inventory",false) into records_inventory from "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" s where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=p_type and s."Aircraft_Series_Subtype"=p_subtype;
 select coalesce(jsonb_agg(item.value||jsonb_build_object('isBaggageDefault',coalesce(spec."ULD_Baggage_Default",false),'baggageMaxPieces',coalesce(spec."ULD_Baggage_Max_Pieces"::text,'')) order by item.value->>'code'),'[]'::jsonb) into rows from jsonb_array_elements(coalesce(result->'rows','[]'::jsonb)) item left join "Basic_Carrier_Record"."Carrier_ULD_Specifications" spec on spec."Carrier_IATA"=p_iata and spec."Aircraft_Type_IATA"=p_type and spec."Aircraft_Series_Subtype"=p_subtype and btrim(spec."ULD_ID")=item.value->>'code';
 return result||jsonb_build_object('rows',rows,'recordsInventory',coalesce(records_inventory,false),'revision',md5(coalesce(result->>'revision','')||coalesce(records_inventory,false)::text||rows::text));
end $$;

create or replace function "Basic_Carrier_Record".save_carrier_ulds_with_baggage_default(p_iata text,p_type text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;baggage_code text;baggage_max integer;
begin
 if jsonb_typeof(p_rows) is distinct from 'array' or (jsonb_array_length(p_rows)>0 and (select count(*) from jsonb_array_elements(p_rows) r where coalesce((r->>'isBaggageDefault')::boolean,false))<>1) then raise exception 'Choose exactly one Default Baggage ULD' using errcode='23514';end if;
 baggage_code:=(select r->>'code' from jsonb_array_elements(p_rows) r where coalesce((r->>'isBaggageDefault')::boolean,false) limit 1);baggage_max:=(select nullif(r->>'baggageMaxPieces','')::integer from jsonb_array_elements(p_rows) r where coalesce((r->>'isBaggageDefault')::boolean,false) limit 1);
 if baggage_code is not null and (baggage_max is null or baggage_max not between 1 and 999) then raise exception 'Enter a Default Baggage ULD planning limit of 1 to 999 pieces' using errcode='23514';end if;
 result:="Basic_Carrier_Record".save_carrier_ulds(p_iata,p_type,p_subtype,p_revision,p_rows);
 update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "ULD_Baggage_Default"=btrim("ULD_ID")=baggage_code,"ULD_Baggage_Max_Pieces"=case when btrim("ULD_ID")=baggage_code then baggage_max else null end where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype;
 return "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);
end $$;

alter function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) rename to get_operational_freight_planning_without_baggage_planning_limit;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning_without_baggage_planning_limit(text,uuid) from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".get_operational_freight_planning(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;flight "Basic_Carrier_Record"."Operational_Flights"%rowtype;uld_code text;piece_capacity integer;position_count integer;planned_count integer;available_count integer;uld_tare numeric;uld_max numeric;uld_volume numeric;bulk_weight numeric;bulk_volume numeric;space_weight numeric;space_volume numeric;remaining_payload numeric;offer numeric;
begin
 p_iata:=upper(btrim(p_iata));result:="Basic_Carrier_Record".get_operational_freight_planning_without_baggage_planning_limit(p_iata,p_operational_flight_id);uld_code:=nullif(result->>'uldCode','');if uld_code is null or result->>'operatingRole'='FREIGHTER' then return result;end if;
 select * into flight from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 select s."ULD_Baggage_Max_Pieces",s."ULD_Tare_Weight",s."ULD_Max_Weight",m."ULD_Volume" into piece_capacity,uld_tare,uld_max,uld_volume from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID") where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA" and s."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and btrim(s."ULD_ID")=uld_code limit 1;if piece_capacity is null then return result;end if;
 position_count:=coalesce(nullif(result->>'uldPositionCount','')::integer,0);select coalesce(sum(ceil(coalesce((item->>'plannedPieces')::numeric,0)/piece_capacity)),0)::integer into planned_count from jsonb_array_elements(coalesce(result->'baggageClasses','[]'::jsonb)) item where coalesce((item->>'plannedPieces')::integer,0)>0;if planned_count=0 and coalesce(nullif(result->>'plannedBaggagePieces','')::integer,0)>0 then planned_count:=ceil((result->>'plannedBaggagePieces')::numeric/piece_capacity)::integer;end if;
 planned_count:=least(position_count,planned_count);available_count:=greatest(0,position_count-planned_count);bulk_weight:=coalesce(nullif(result->>'availableBulkWeight','')::numeric,0);bulk_volume:=coalesce(nullif(result->>'availableBulkVolume','')::numeric,0);space_weight:=available_count*greatest(0,uld_max-uld_tare)+bulk_weight;space_volume:=available_count*coalesce(uld_volume,0)+bulk_volume;remaining_payload:=nullif(result->>'remainingPayload','')::numeric;offer:=least(remaining_payload,space_weight);
 return result||jsonb_build_object('baggagePiecesPerUld',piece_capacity,'plannedBaggageUldPositions',planned_count,'availableUldPositions',available_count,'spaceWeightCapacity',space_weight,'remainingHoldWeight',space_weight,'remainingHoldVolume',round(space_volume,2),'totalAvailableCargoVolume',round(space_volume,2),'cargoOfferWeight',offer,'limitingFactor',case when offer=remaining_payload then 'PAYLOAD' else 'HOLD_WEIGHT' end);
end $$;

revoke all on function "Basic_Carrier_Record".save_carrier_ulds_with_baggage_default(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_ulds_with_baggage_default(text,text,text,text,jsonb) to authenticated;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
