begin;

create table "Basic_Carrier_Record"."Operational_Freight_Acceptance"(
  "Operational_Flight_ID" uuid primary key references "Basic_Carrier_Record"."Operational_Flights"("Operational_Flight_ID") on update cascade on delete cascade,
  "Carrier_IATA" varchar(3) not null references "Basic_Carrier_Record"."MASTER_Carrier_Contact"("Carrier_IATA") on update cascade on delete restrict,
  "Status" text not null default 'ACCEPTED' check("Status" in('ACCEPTED')),
  "Source" text not null check("Source" in('MANUAL','CSV','AHM581','MIXED')),
  "Source_Reference" text check("Source_Reference" is null or char_length("Source_Reference")<=200),
  "Raw_Message" text check("Raw_Message" is null or char_length("Raw_Message")<=100000),
  "Version" integer not null default 1 check("Version">0),
  "Created_At" timestamptz not null default now(),
  "Created_By" uuid not null default auth.uid(),
  "Updated_At" timestamptz not null default now(),
  "Updated_By" uuid not null default auth.uid()
);

create table "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items"(
  "Line_ID" uuid primary key default gen_random_uuid(),
  "Operational_Flight_ID" uuid not null references "Basic_Carrier_Record"."Operational_Freight_Acceptance"("Operational_Flight_ID") on update cascade on delete cascade,
  "Carrier_IATA" varchar(3) not null references "Basic_Carrier_Record"."MASTER_Carrier_Contact"("Carrier_IATA") on update cascade on delete restrict,
  "Sequence_Number" integer not null check("Sequence_Number" between 1 and 250),
  "Load_Type" text not null check("Load_Type" in('ULD','BULK')),
  "ULD_ID" varchar(12),
  "Gross_Weight" numeric(10,2) not null check("Gross_Weight">0),
  "Net_Weight" numeric(10,2) check("Net_Weight">=0 and "Net_Weight"<="Gross_Weight"),
  "Station_Of_Unloading" char(3) not null check("Station_Of_Unloading"~'^[A-Z]{3}$'),
  "Destination" char(3) not null check("Destination"~'^[A-Z]{3}$'),
  "Commodity" text not null check("Commodity" in('CARGO','MAIL','SPECIAL_LOAD','DANGEROUS_GOODS')),
  "Pieces" integer check("Pieces">=0),
  "Volume_M3" numeric(10,3) check("Volume_M3">=0),
  "Special_Handling_Codes" text[] not null default '{}',
  "Dangerous_Goods" boolean not null default false,
  "Remarks" text check("Remarks" is null or char_length("Remarks")<=1000),
  "Source" text not null check("Source" in('MANUAL','CSV','AHM581')),
  "Source_Reference" text check("Source_Reference" is null or char_length("Source_Reference")<=200),
  constraint "operational_freight_acceptance_item_shape" check(
    ("Load_Type"='ULD' and "ULD_ID"~'^[A-Z]{3}[A-Z0-9]{4,8}$' and "Volume_M3" is null)
    or ("Load_Type"='BULK' and "ULD_ID" is null)
  ),
  unique("Operational_Flight_ID","Sequence_Number"),
  unique("Operational_Flight_ID","ULD_ID")
);

create index "operational_freight_acceptance_carrier_idx" on "Basic_Carrier_Record"."Operational_Freight_Acceptance"("Carrier_IATA","Updated_At" desc);
create index "operational_freight_acceptance_items_flight_idx" on "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items"("Operational_Flight_ID","Sequence_Number");

alter table "Basic_Carrier_Record"."Operational_Freight_Acceptance" enable row level security;
alter table "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items" enable row level security;
grant select on "Basic_Carrier_Record"."Operational_Freight_Acceptance" to authenticated;
grant select on "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items" to authenticated;
create policy "operational_freight_acceptance_select" on "Basic_Carrier_Record"."Operational_Freight_Acceptance" for select to authenticated using((select private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW'))or(select private.has_global_permission('LOAD_CONTROL_VIEW')));
create policy "operational_freight_acceptance_items_select" on "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items" for select to authenticated using((select private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW'))or(select private.has_global_permission('LOAD_CONTROL_VIEW')));

create or replace function "Basic_Carrier_Record".get_operational_freight_acceptance(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare f "Basic_Carrier_Record"."Operational_Flights"%rowtype;h "Basic_Carrier_Record"."Operational_Freight_Acceptance"%rowtype;planning jsonb;items jsonb;total numeric:=0;offer numeric;applicable boolean;can_operate boolean;
begin
 p_iata:=upper(btrim(p_iata));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW')or private.has_global_permission('LOAD_CONTROL_VIEW'))then raise exception 'Load Control access denied' using errcode='42501';end if;
 can_operate:=private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE');
 select*into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
 planning:="Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);applicable:=coalesce((planning->>'applicable')::boolean,false);offer:=nullif(planning->>'cargoOfferWeight','')::numeric;
 if not applicable then return jsonb_build_object('applicable',false,'canEdit',can_operate,'version',0,'status','EMPTY','source',null,'sourceReference',null,'rawMessage',null,'items','[]'::jsonb,'totalWeight',0,'cargoOfferWeight',offer,'remainingOffer',offer,'withinOffer',true,'updatedAt',null);end if;
 select*into h from "Basic_Carrier_Record"."Operational_Freight_Acceptance" where "Operational_Flight_ID"=p_operational_flight_id and "Carrier_IATA"=p_iata;
 select coalesce(jsonb_agg(jsonb_build_object('lineId',i."Line_ID",'loadType',i."Load_Type",'uldId',i."ULD_ID",'grossWeight',i."Gross_Weight",'netWeight',i."Net_Weight",'unloadingStation',btrim(i."Station_Of_Unloading"),'destination',btrim(i."Destination"),'commodity',i."Commodity",'pieces',i."Pieces",'volume',i."Volume_M3",'specialHandlingCodes',to_jsonb(i."Special_Handling_Codes"),'dangerousGoods',i."Dangerous_Goods",'remarks',i."Remarks",'source',i."Source",'sourceReference',i."Source_Reference")order by i."Sequence_Number"),'[]'::jsonb),coalesce(sum(i."Gross_Weight"),0)into items,total from "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items" i where i."Operational_Flight_ID"=p_operational_flight_id and i."Carrier_IATA"=p_iata;
 return jsonb_build_object('applicable',true,'canEdit',can_operate,'version',coalesce(h."Version",0),'status',case when h."Operational_Flight_ID"is null then'EMPTY'else h."Status"end,'source',h."Source",'sourceReference',h."Source_Reference",'rawMessage',h."Raw_Message",'items',items,'totalWeight',total,'cargoOfferWeight',offer,'remainingOffer',case when offer is null then null else offer-total end,'withinOffer',offer is null or total<=offer,'updatedAt',h."Updated_At");
end;$$;
revoke all on function "Basic_Carrier_Record".get_operational_freight_acceptance(text,uuid)from public,anon;grant execute on function "Basic_Carrier_Record".get_operational_freight_acceptance(text,uuid)to authenticated;

create or replace function "Basic_Carrier_Record".save_operational_freight_acceptance(p_iata text,p_operational_flight_id uuid,p_version integer,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare f "Basic_Carrier_Record"."Operational_Flights"%rowtype;h "Basic_Carrier_Record"."Operational_Freight_Acceptance"%rowtype;planning jsonb;item jsonb;seq integer:=0;source text:=upper(btrim(p_values->>'source'));source_ref text:=nullif(btrim(p_values->>'sourceReference'),'');raw_message text:=nullif(btrim(p_values->>'rawMessage'),'');load_type text;uld_id text;gross numeric;net numeric;unload text;destination text;commodity text;pieces integer;volume numeric;item_source text;item_ref text;remarks text;shcs text[];dg boolean;total numeric:=0;offer numeric;seen_uld text[]:='{}';
begin
 p_iata:=upper(btrim(p_iata));
 if(select auth.uid())is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE')or private.has_global_permission('LOAD_CONTROL_OPERATE'))then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object'or source not in('MANUAL','CSV','AHM581','MIXED')or jsonb_typeof(p_values->'items')<>'array'or jsonb_array_length(p_values->'items')not between 1 and 250 or char_length(coalesce(source_ref,''))>200 or char_length(coalesce(raw_message,''))>100000 then raise exception 'Check the freight acceptance statement' using errcode='22023';end if;
 select*into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
 planning:="Basic_Carrier_Record".get_operational_freight_planning(p_iata,p_operational_flight_id);if not coalesce((planning->>'applicable')::boolean,false)then raise exception 'Freight acceptance is available for freighter aircraft' using errcode='23514';end if;if not coalesce((planning->>'ready')::boolean,false)then raise exception 'Complete the Cargo Offer before accepting freight' using errcode='55000';end if;offer:=nullif(planning->>'cargoOfferWeight','')::numeric;
 select*into h from "Basic_Carrier_Record"."Operational_Freight_Acceptance" where "Operational_Flight_ID"=p_operational_flight_id for update;
 if found then if h."Version"<>p_version then raise exception 'The acceptance statement changed. Reload before saving.' using errcode='40001';end if;else if p_version<>0 then raise exception 'The acceptance statement changed. Reload before saving.' using errcode='40001';end if;end if;
 for item in select value from jsonb_array_elements(p_values->'items')loop seq:=seq+1;load_type:=upper(btrim(item->>'loadType'));uld_id:=nullif(upper(btrim(item->>'uldId')),'');gross:=nullif(item->>'grossWeight','')::numeric;net:=nullif(item->>'netWeight','')::numeric;unload:=upper(btrim(item->>'unloadingStation'));destination:=upper(btrim(item->>'destination'));commodity:=upper(btrim(item->>'commodity'));pieces:=nullif(item->>'pieces','')::integer;volume:=nullif(item->>'volume','')::numeric;item_source:=upper(btrim(item->>'source'));item_ref:=nullif(btrim(item->>'sourceReference'),'');remarks:=nullif(btrim(item->>'remarks'),'');dg:=coalesce((item->>'dangerousGoods')::boolean,false)or commodity='DANGEROUS_GOODS';select coalesce(array_agg(upper(btrim(value))),array[]::text[])into shcs from jsonb_array_elements_text(coalesce(item->'specialHandlingCodes','[]'::jsonb));
  if load_type not in('ULD','BULK')or gross is null or gross<=0 or(net is not null and(net<0 or net>gross))or unload!~'^[A-Z]{3}$'or destination!~'^[A-Z]{3}$'or commodity not in('CARGO','MAIL','SPECIAL_LOAD','DANGEROUS_GOODS')or item_source not in('MANUAL','CSV','AHM581')or(pieces is not null and pieces<0)or(volume is not null and volume<0)or char_length(coalesce(item_ref,''))>200 or char_length(coalesce(remarks,''))>1000 then raise exception 'Check freight acceptance row %',seq using errcode='22023';end if;
  if(load_type='ULD'and(uld_id is null or uld_id!~'^[A-Z]{3}[A-Z0-9]{4,8}$'or volume is not null))or(load_type='BULK'and uld_id is not null)then raise exception 'Check ULD/Bulk identity on row %',seq using errcode='22023';end if;
  if uld_id is not null then if uld_id=any(seen_uld)then raise exception 'ULD % appears more than once',uld_id using errcode='23505';end if;seen_uld:=array_append(seen_uld,uld_id);end if;total:=total+gross;
 end loop;
 if offer is not null and total>offer then raise exception 'Accepted gross weight exceeds the Cargo Offer by % KG',round(total-offer) using errcode='23514';end if;
 insert into "Basic_Carrier_Record"."Operational_Freight_Acceptance"("Operational_Flight_ID","Carrier_IATA","Status","Source","Source_Reference","Raw_Message")values(p_operational_flight_id,p_iata,'ACCEPTED',source,source_ref,raw_message)on conflict("Operational_Flight_ID")do update set "Status"='ACCEPTED',"Source"=excluded."Source","Source_Reference"=excluded."Source_Reference","Raw_Message"=excluded."Raw_Message","Version"="Basic_Carrier_Record"."Operational_Freight_Acceptance"."Version"+1,"Updated_At"=now(),"Updated_By"=auth.uid();
 delete from "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items"where"Operational_Flight_ID"=p_operational_flight_id;
 seq:=0;for item in select value from jsonb_array_elements(p_values->'items')loop seq:=seq+1;load_type:=upper(btrim(item->>'loadType'));uld_id:=nullif(upper(btrim(item->>'uldId')),'');gross:=(item->>'grossWeight')::numeric;net:=nullif(item->>'netWeight','')::numeric;unload:=upper(btrim(item->>'unloadingStation'));destination:=upper(btrim(item->>'destination'));commodity:=upper(btrim(item->>'commodity'));pieces:=nullif(item->>'pieces','')::integer;volume:=nullif(item->>'volume','')::numeric;item_source:=upper(btrim(item->>'source'));item_ref:=nullif(btrim(item->>'sourceReference'),'');remarks:=nullif(btrim(item->>'remarks'),'');dg:=coalesce((item->>'dangerousGoods')::boolean,false)or commodity='DANGEROUS_GOODS';select coalesce(array_agg(upper(btrim(value))),array[]::text[])into shcs from jsonb_array_elements_text(coalesce(item->'specialHandlingCodes','[]'::jsonb));insert into "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items"("Operational_Flight_ID","Carrier_IATA","Sequence_Number","Load_Type","ULD_ID","Gross_Weight","Net_Weight","Station_Of_Unloading","Destination","Commodity","Pieces","Volume_M3","Special_Handling_Codes","Dangerous_Goods","Remarks","Source","Source_Reference")values(p_operational_flight_id,p_iata,seq,load_type,uld_id,gross,net,unload,destination,commodity,pieces,volume,shcs,dg,remarks,item_source,item_ref);end loop;
 update "Basic_Carrier_Record"."Operational_Flights"set"Status"=case when"Status"='INITIATED'then'LOAD_PLANNING'else"Status"end where"Operational_Flight_ID"=p_operational_flight_id and"Carrier_IATA"=p_iata;
 return "Basic_Carrier_Record".get_operational_freight_acceptance(p_iata,p_operational_flight_id);
end;$$;
revoke all on function "Basic_Carrier_Record".save_operational_freight_acceptance(text,uuid,integer,jsonb)from public,anon;grant execute on function "Basic_Carrier_Record".save_operational_freight_acceptance(text,uuid,integer,jsonb)to authenticated;
notify pgrst,'reload schema';
commit;
