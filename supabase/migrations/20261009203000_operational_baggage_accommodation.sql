begin;

create table if not exists "Basic_Carrier_Record"."Operational_Baggage_Accommodation"(
  "Carrier_IATA" text not null,
  "Operational_Flight_ID" uuid not null,
  "Version" integer not null default 1 check ("Version">0),
  "ULD_Count" integer not null check ("ULD_Count">=0),
  "ULD_Net_Weight" numeric not null check ("ULD_Net_Weight">=0),
  "Bulk_Net_Weight" numeric not null check ("Bulk_Net_Weight">=0),
  "Accepted_At" timestamptz not null default now(),
  "Accepted_By" uuid not null,
  primary key("Carrier_IATA","Operational_Flight_ID"),
  foreign key("Operational_Flight_ID") references "Basic_Carrier_Record"."Operational_Flights"("Operational_Flight_ID") on delete cascade
);
alter table "Basic_Carrier_Record"."Operational_Baggage_Accommodation" enable row level security;
revoke all on table "Basic_Carrier_Record"."Operational_Baggage_Accommodation" from public,anon,authenticated;

create or replace function "Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare planning jsonb; saved "Basic_Carrier_Record"."Operational_Baggage_Accommodation"%rowtype;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')) then raise exception 'Load Control access denied' using errcode='42501';end if;
 planning:="Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);
 if planning->>'operatingRole'='FREIGHTER' then return null;end if;
 select * into saved from "Basic_Carrier_Record"."Operational_Baggage_Accommodation" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 return jsonb_build_object(
  'status',case when found then 'ACCEPTED' else 'PROPOSED' end,
  'version',case when found then saved."Version" else 0 end,
  'uldCount',case when found then saved."ULD_Count" else coalesce((planning->>'plannedBaggageUldPositions')::integer,0) end,
  'uldNetWeight',case when found then saved."ULD_Net_Weight" else coalesce((planning->>'plannedBaggageWeight')::numeric,0) end,
  'bulkNetWeight',case when found then saved."Bulk_Net_Weight" else 0 end,
  'totalNetWeight',coalesce((planning->>'plannedBaggageWeight')::numeric,0),
  'uldCode',planning->>'uldCode',
  'maximumUldCount',coalesce((planning->>'uldPositionCount')::integer,0),
  'holdSystem',planning->>'holdSystem'
 );
end $$;
revoke all on function "Basic_Carrier_Record".get_operational_baggage_accommodation(text,uuid) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_baggage_accommodation(text,uuid) to authenticated;

create or replace function "Basic_Carrier_Record".save_operational_baggage_accommodation(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare planning jsonb; current_version integer; uld_count integer; uld_weight numeric; bulk_weight numeric; total_weight numeric; hold_system text; max_uld integer;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE')) then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' then raise exception 'Check the baggage accommodation' using errcode='22023';end if;
 begin uld_count:=(p_values->>'uldCount')::integer;uld_weight:=(p_values->>'uldNetWeight')::numeric;bulk_weight:=(p_values->>'bulkNetWeight')::numeric;exception when others then raise exception 'Enter valid baggage accommodation values' using errcode='22023';end;
 planning:="Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);
 if planning->>'operatingRole'='FREIGHTER' then raise exception 'Baggage accommodation is available for passenger aircraft' using errcode='23514';end if;
 total_weight:=coalesce((planning->>'plannedBaggageWeight')::numeric,0);hold_system:=planning->>'holdSystem';max_uld:=coalesce((planning->>'uldPositionCount')::integer,0);
 if uld_count<0 or uld_count>max_uld or uld_weight<0 or bulk_weight<0 or abs((uld_weight+bulk_weight)-total_weight)>0.5 then raise exception 'Allocate the complete planned baggage weight between ULD and Bulk accommodation' using errcode='23514';end if;
 if (uld_count=0 and uld_weight>0) or (uld_count>0 and uld_weight<=0) then raise exception 'The baggage ULD count and ULD baggage weight must agree' using errcode='23514';end if;
 if hold_system='ULD' and bulk_weight>0 then raise exception 'This aircraft has no Bulk baggage accommodation' using errcode='23514';end if;
 select "Version" into current_version from "Basic_Carrier_Record"."Operational_Baggage_Accommodation" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if coalesce(current_version,0)<>p_expected_version then raise exception 'The baggage accommodation changed. Reload before saving.' using errcode='40001';end if;
 insert into "Basic_Carrier_Record"."Operational_Baggage_Accommodation"("Carrier_IATA","Operational_Flight_ID","Version","ULD_Count","ULD_Net_Weight","Bulk_Net_Weight","Accepted_By") values(p_iata,p_operational_flight_id,current_version+1,uld_count,uld_weight,bulk_weight,(select auth.uid()))
 on conflict("Carrier_IATA","Operational_Flight_ID") do update set "Version"=excluded."Version","ULD_Count"=excluded."ULD_Count","ULD_Net_Weight"=excluded."ULD_Net_Weight","Bulk_Net_Weight"=excluded."Bulk_Net_Weight","Accepted_At"=now(),"Accepted_By"=excluded."Accepted_By";
 return "Basic_Carrier_Record".get_operational_baggage_accommodation(p_iata,p_operational_flight_id);
end $$;
revoke all on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_operational_baggage_accommodation(text,uuid,integer,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
