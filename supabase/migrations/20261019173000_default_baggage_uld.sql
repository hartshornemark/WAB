begin;

alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications"
  add column if not exists "ULD_Baggage_Default" boolean not null default false;

create unique index if not exists carrier_uld_one_baggage_default_idx
on "Basic_Carrier_Record"."Carrier_ULD_Specifications"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
where "ULD_Baggage_Default";

with preferred as(
  select distinct on(p."Carrier_IATA",p."Aircraft_Type_IATA",p."Aircraft_Series_Subtype")
    p."Carrier_IATA",p."Aircraft_Type_IATA",p."Aircraft_Series_Subtype",btrim(p."ULD_Code") uld_code
  from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
  join "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
    on s."Carrier_IATA"=p."Carrier_IATA"
   and s."Aircraft_Type_IATA"=p."Aircraft_Type_IATA"
   and s."Aircraft_Series_Subtype"=p."Aircraft_Series_Subtype"
   and btrim(s."ULD_ID")=btrim(p."ULD_Code")
  where p."ULD_Row_Type"='POSITION'
  group by p."Carrier_IATA",p."Aircraft_Type_IATA",p."Aircraft_Series_Subtype",btrim(p."ULD_Code")
  order by p."Carrier_IATA",p."Aircraft_Type_IATA",p."Aircraft_Series_Subtype",count(*) desc,btrim(p."ULD_Code")
), fallback as(
  select distinct on(s."Carrier_IATA",s."Aircraft_Type_IATA",s."Aircraft_Series_Subtype")
    s."Carrier_IATA",s."Aircraft_Type_IATA",s."Aircraft_Series_Subtype",btrim(s."ULD_ID") uld_code
  from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
  order by s."Carrier_IATA",s."Aircraft_Type_IATA",s."Aircraft_Series_Subtype",s."ULD_Default" desc,btrim(s."ULD_ID")
), chosen as(
  select f."Carrier_IATA",f."Aircraft_Type_IATA",f."Aircraft_Series_Subtype",coalesce(p.uld_code,f.uld_code) uld_code
  from fallback f left join preferred p using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
)
update "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
set "ULD_Baggage_Default"=btrim(s."ULD_ID")=c.uld_code
from chosen c
where s."Carrier_IATA"=c."Carrier_IATA" and s."Aircraft_Type_IATA"=c."Aircraft_Type_IATA"
  and s."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype";

create or replace function "Basic_Carrier_Record".get_carrier_ulds(p_iata text,p_type text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;records_inventory boolean;rows jsonb;
begin
 result:="Basic_Carrier_Record".get_carrier_ulds_without_inventory_flag(p_iata,p_type,p_subtype);
 select coalesce(s."Records_ULD_Inventory",false) into records_inventory from "Basic_Carrier_Record"."Carrier_Aircraft_B5_Settings" s where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=p_type and s."Aircraft_Series_Subtype"=p_subtype;
 select coalesce(jsonb_agg(item.value||jsonb_build_object('isBaggageDefault',coalesce(spec."ULD_Baggage_Default",false)) order by item.value->>'code'),'[]'::jsonb) into rows
 from jsonb_array_elements(coalesce(result->'rows','[]'::jsonb)) item
 left join "Basic_Carrier_Record"."Carrier_ULD_Specifications" spec on spec."Carrier_IATA"=p_iata and spec."Aircraft_Type_IATA"=p_type and spec."Aircraft_Series_Subtype"=p_subtype and btrim(spec."ULD_ID")=item.value->>'code';
 return result||jsonb_build_object('rows',rows,'recordsInventory',coalesce(records_inventory,false),'revision',md5(coalesce(result->>'revision','')||coalesce(records_inventory,false)::text||rows::text));
end $$;

create or replace function "Basic_Carrier_Record".save_carrier_ulds_with_baggage_default(p_iata text,p_type text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;baggage_code text;
begin
 if jsonb_typeof(p_rows) is distinct from 'array' or (jsonb_array_length(p_rows)>0 and (select count(*) from jsonb_array_elements(p_rows) r where coalesce((r->>'isBaggageDefault')::boolean,false))<>1) then raise exception 'Choose exactly one Default Baggage ULD' using errcode='23514';end if;
 baggage_code:=(select r->>'code' from jsonb_array_elements(p_rows) r where coalesce((r->>'isBaggageDefault')::boolean,false) limit 1);
 result:="Basic_Carrier_Record".save_carrier_ulds(p_iata,p_type,p_subtype,p_revision,p_rows);
 update "Basic_Carrier_Record"."Carrier_ULD_Specifications" set "ULD_Baggage_Default"=btrim("ULD_ID")=baggage_code
 where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype;
 return "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);
end $$;

alter function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid)
  rename to get_operational_freight_planning_without_configured_baggage_uld;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning_without_configured_baggage_uld(text,uuid) from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".get_operational_freight_planning(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;flight "Basic_Carrier_Record"."Operational_Flights"%rowtype;default_code text;default_type text;position_count integer;uld_tare numeric;uld_max numeric;uld_volume numeric;baggage_pieces integer;baggage_weight numeric;piece_capacity integer;configured_piece_volume numeric;weight_capacity integer;volume_capacity integer;planned_count integer;available_count integer;bulk_weight numeric;bulk_volume numeric;space_weight numeric;space_volume numeric;remaining_payload numeric;offer numeric;
begin
 p_iata:=upper(btrim(p_iata));result:="Basic_Carrier_Record".get_operational_freight_planning_without_configured_baggage_uld(p_iata,p_operational_flight_id);
 if result->>'operatingRole'='FREIGHTER' then return result;end if;
 select * into flight from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 select btrim(s."ULD_ID"),btrim(s."ULD_Type"),s."ULD_Tare_Weight",s."ULD_Max_Weight",m."ULD_Volume" into default_code,default_type,uld_tare,uld_max,uld_volume from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=coalesce(s."Master_ULD_ID",s."ULD_ID") where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA" and s."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and s."ULD_Baggage_Default" limit 1;
 if default_code is null then return result;end if;
 select count(*)::integer into position_count from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=flight."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=flight."Aircraft_Series_Subtype" and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Code")=default_code;
 if position_count=0 then return result;end if;
 baggage_pieces:=coalesce(nullif(result->>'plannedBaggagePieces','')::integer,0);baggage_weight:=coalesce(nullif(result->>'plannedBaggageWeight','')::numeric,0);
 if baggage_pieces>0 and baggage_weight>0 and uld_max>uld_tare then weight_capacity:=floor((uld_max-uld_tare)/(baggage_weight/baggage_pieces))::integer;end if;
 select max(p."Average_Bag_Volume") into configured_piece_volume from "Basic_Carrier_Record"."Carrier_Planning_Assumptions" p where p."Carrier_IATA"=p_iata and p."Average_Bag_Volume">0;
 if configured_piece_volume>0 and uld_volume>0 then volume_capacity:=floor(uld_volume/configured_piece_volume)::integer;end if;
 piece_capacity:=case when weight_capacity>0 and volume_capacity>0 then least(weight_capacity,volume_capacity) when volume_capacity>0 then volume_capacity when weight_capacity>0 then weight_capacity else null end;
 planned_count:=case when baggage_pieces>0 and piece_capacity>0 then least(position_count,ceil(baggage_pieces::numeric/piece_capacity)::integer) else 0 end;available_count:=greatest(0,position_count-planned_count);
 bulk_weight:=coalesce(nullif(result->>'availableBulkWeight','')::numeric,0);bulk_volume:=coalesce(nullif(result->>'availableBulkVolume','')::numeric,0);space_weight:=available_count*greatest(0,uld_max-uld_tare)+bulk_weight;space_volume:=available_count*coalesce(uld_volume,0)+bulk_volume;remaining_payload:=nullif(result->>'remainingPayload','')::numeric;offer:=least(remaining_payload,space_weight);
 return result||jsonb_build_object('uldCode',default_code,'primaryUldType',default_type,'uldPositionCount',position_count,'baggagePiecesPerUld',piece_capacity,'plannedBaggageUldPositions',planned_count,'availableUldPositions',available_count,'spaceWeightCapacity',space_weight,'remainingHoldWeight',space_weight,'remainingHoldVolume',round(space_volume,2),'totalAvailableCargoVolume',round(space_volume,2),'cargoOfferWeight',offer,'limitingFactor',case when offer=remaining_payload then 'PAYLOAD' else 'HOLD_WEIGHT' end);
end $$;

revoke all on function "Basic_Carrier_Record".save_carrier_ulds_with_baggage_default(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_ulds_with_baggage_default(text,text,text,text,jsonb) to authenticated;
revoke all on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_freight_planning(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
