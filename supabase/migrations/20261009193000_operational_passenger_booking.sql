begin;

create table "Basic_Carrier_Record"."Operational_Passenger_Bookings"(
  "Operational_Flight_ID" uuid primary key references "Basic_Carrier_Record"."Operational_Flights"("Operational_Flight_ID") on update cascade on delete cascade,
  "Carrier_IATA" varchar(2) not null,
  "Booked_By_Class" jsonb not null default '{}'::jsonb check(jsonb_typeof("Booked_By_Class")='object'),
  "Version" integer not null default 1 check("Version">0),
  "Updated_By" uuid not null default auth.uid(),
  "Updated_At" timestamptz not null default now()
);
create index "operational_passenger_booking_carrier_idx" on "Basic_Carrier_Record"."Operational_Passenger_Bookings"("Carrier_IATA","Updated_At" desc);
alter table "Basic_Carrier_Record"."Operational_Passenger_Bookings" enable row level security;
revoke all on "Basic_Carrier_Record"."Operational_Passenger_Bookings" from public,anon,authenticated;
grant select on "Basic_Carrier_Record"."Operational_Passenger_Bookings" to authenticated;
create policy "operational_passenger_booking_select" on "Basic_Carrier_Record"."Operational_Passenger_Bookings" for select to authenticated using(
  private.has_carrier_permission("Carrier_IATA",'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')
);

create or replace function "Basic_Carrier_Record".get_operational_passenger_booking(p_iata text,p_operational_flight_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare f "Basic_Carrier_Record"."Operational_Flights"%rowtype; aircraft "Basic_Carrier_Record"."Basic_Aircraft_Data"%rowtype; b record; c record; classes jsonb:='[]'::jsonb; missing jsonb:='[]'::jsonb; booked integer; pax_weight numeric; class_weight numeric; total_booked integer:=0; total_weight numeric:=0; unit text; can_operate boolean;
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_VIEW') or private.has_global_permission('LOAD_CONTROL_VIEW')) then raise exception 'Load Control access denied' using errcode='42501';end if;
 can_operate:=private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE');
 select * into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id;
 if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
 select * into aircraft from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=f."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype";
 if not found then raise exception 'Aircraft configuration not found' using errcode='23503';end if;
 if aircraft."Aircraft_Operating_Role"='FREIGHTER' then return jsonb_build_object('applicable',false,'operatingRole',aircraft."Aircraft_Operating_Role",'canEdit',can_operate,'version',0,'status','EMPTY','weightBasis',null,'flightVariation',null,'classes','[]'::jsonb,'totalBooked',0,'totalPassengerWeight',0,'ready',true,'missing','[]'::jsonb,'updatedAt',null);end if;
 select * into b from "Basic_Carrier_Record"."Operational_Passenger_Bookings" where "Operational_Flight_ID"=p_operational_flight_id and "Carrier_IATA"=p_iata;
 select case when "Carrier_Unit_Weight_LB" and not "Carrier_Unit_Weight_KG" then 'LB' else 'KG' end into unit from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata;
 for c in
  select x.priority,btrim(x.code) code,btrim(x.name) name from "Basic_Carrier_Record"."Carrier_Class_Codes" cc cross join lateral(values(1,cc."Carrier_Class_1_Code"::text,cc."Carrier_Class_1_Name"::text),(2,cc."Carrier_Class_2_Code"::text,cc."Carrier_Class_2_Name"::text),(3,cc."Carrier_Class_3_Code"::text,cc."Carrier_Class_3_Name"::text),(4,cc."Carrier_Class_4_Code"::text,cc."Carrier_Class_4_Name"::text))x(priority,code,name) where cc."Carrier_IATA"=p_iata and x.code is not null order by x.priority
 loop
  booked:=coalesce((b."Booked_By_Class"->>c.code)::integer,0);
  select case when coalesce(q.adult,(q.male+q.female)/2) is null then null else round((coalesce(q.adult,(q.male+q.female)/2)+case when q.includes_hand then 0 else coalesce(q.hand_weight,0) end)*case when unit='LB' then 0.45359237 else 1 end,2) end into pax_weight from(
   select w."Adult"::numeric adult,w."Male"::numeric male,w."Female"::numeric female,w."Passenger_Weights_Include_Handbaggage" includes_hand,w."Hand_Baggage_Weight"::numeric hand_weight,1 priority from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w where w."Carrier_IATA"=p_iata and w."Class_Code"=c.code and ((f."Passenger_Weight_Basis"='VARIATION' and w."Flight_Type_Variation"=f."Passenger_Flight_Variation") or (f."Passenger_Weight_Basis"<>'VARIATION' and w."Flight_Type_Variation" is null))
   union all select w."Adult",w."Male",w."Female",w."Passenger_Weights_Include_Handbaggage",w."Hand_Baggage_Weight",2 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w where f."Passenger_Weight_Basis"='VARIATION' and w."Carrier_IATA"=p_iata and w."Class_Code" is null and w."Flight_Type_Variation"=f."Passenger_Flight_Variation"
   union all select w."Adult",w."Male",w."Female",w."Passenger_Weights_Include_Handbaggage",w."Hand_Baggage_Weight",3 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_BYCLASS" w where f."Passenger_Weight_Basis"='VARIATION' and w."Carrier_IATA"=p_iata and w."Class_Code"=c.code and w."Flight_Type_Variation" is null
   union all select w."Adult",w."Male",w."Female",w."Passenger_Weights_Include_Handbaggage",w."Hand_Baggage_Weight",9 from "Basic_Carrier_Record"."Carrier_Passenger_Weights_ALLFLIGHTS" w where w."Carrier_IATA"=p_iata order by priority limit 1
  )q;
  class_weight:=case when pax_weight is null then null else round(booked*pax_weight,2) end;
  if pax_weight is null then missing:=missing||jsonb_build_array('PASSENGER_WEIGHT_'||c.code);end if;
  total_booked:=total_booked+booked;total_weight:=total_weight+coalesce(class_weight,0);
  classes:=classes||jsonb_build_array(jsonb_build_object('code',c.code,'name',c.name,'booked',booked,'planningWeight',pax_weight,'passengerWeight',class_weight));
 end loop;
 if jsonb_array_length(classes)=0 then missing:=missing||jsonb_build_array('CLASS_CODES');end if;
 if f."Passenger_Weight_Basis" is null then missing:=missing||jsonb_build_array('PASSENGER_WEIGHT_BASIS');end if;
 return jsonb_build_object('applicable',true,'operatingRole',aircraft."Aircraft_Operating_Role",'canEdit',can_operate,'version',coalesce(b."Version",0),'status',case when b."Operational_Flight_ID" is null then 'EMPTY' else 'BOOKED' end,'weightBasis',f."Passenger_Weight_Basis",'flightVariation',f."Passenger_Flight_Variation",'classes',classes,'totalBooked',total_booked,'totalPassengerWeight',total_weight,'ready',jsonb_array_length(missing)=0,'missing',missing,'updatedAt',b."Updated_At");
end $$;

create or replace function "Basic_Carrier_Record".save_operational_passenger_booking(p_iata text,p_operational_flight_id uuid,p_expected_version integer,p_values jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare f "Basic_Carrier_Record"."Operational_Flights"%rowtype; current_version integer:=0; item jsonb; code text; booked integer; values_by_class jsonb:='{}'::jsonb; seen text[]:='{}';
begin
 p_iata:=upper(btrim(p_iata));
 if (select auth.uid()) is null or not(private.has_carrier_permission(p_iata,'LOAD_CONTROL_OPERATE') or private.has_global_permission('LOAD_CONTROL_OPERATE')) then raise exception 'Load Control operation denied' using errcode='42501';end if;
 if p_values is null or jsonb_typeof(p_values->'classes') is distinct from 'array' or jsonb_array_length(p_values->'classes') not between 1 and 4 then raise exception 'Enter the booked passenger load by class' using errcode='22023';end if;
 select * into f from "Basic_Carrier_Record"."Operational_Flights" where "Carrier_IATA"=p_iata and "Operational_Flight_ID"=p_operational_flight_id for update;
 if not found then raise exception 'Operational flight not found' using errcode='P0002';end if;
 if exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=f."Aircraft_Type_IATA" and a."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and a."Aircraft_Operating_Role"='FREIGHTER') then raise exception 'Passenger bookings do not apply to freighter aircraft' using errcode='23514';end if;
 select "Version" into current_version from "Basic_Carrier_Record"."Operational_Passenger_Bookings" where "Operational_Flight_ID"=p_operational_flight_id and "Carrier_IATA"=p_iata for update;current_version:=coalesce(current_version,0);
 if current_version<>p_expected_version then raise exception 'The passenger booking changed. Reload before saving.' using errcode='40001';end if;
 for item in select value from jsonb_array_elements(p_values->'classes') loop
  code:=upper(btrim(item->>'code'));if code!~'^[A-Z]$' or code=any(seen) or (item->>'booked')!~'^[0-9]{1,3}$' then raise exception 'Check the booked passenger entries' using errcode='22023';end if;booked:=(item->>'booked')::integer;
  if not exists(select 1 from "Basic_Carrier_Record"."Carrier_Class_Codes" c where c."Carrier_IATA"=p_iata and code=any(array[c."Carrier_Class_1_Code"::text,c."Carrier_Class_2_Code"::text,c."Carrier_Class_3_Code"::text,c."Carrier_Class_4_Code"::text])) then raise exception 'Select a configured class' using errcode='23503';end if;
  seen:=array_append(seen,code);values_by_class:=values_by_class||jsonb_build_object(code,booked);
 end loop;
 insert into "Basic_Carrier_Record"."Operational_Passenger_Bookings"("Operational_Flight_ID","Carrier_IATA","Booked_By_Class","Version","Updated_By","Updated_At") values(p_operational_flight_id,p_iata,values_by_class,1,auth.uid(),now()) on conflict("Operational_Flight_ID") do update set "Booked_By_Class"=excluded."Booked_By_Class","Version"="Basic_Carrier_Record"."Operational_Passenger_Bookings"."Version"+1,"Updated_By"=auth.uid(),"Updated_At"=now();
 return "Basic_Carrier_Record".get_operational_passenger_booking(p_iata,p_operational_flight_id);
end $$;

revoke all on function "Basic_Carrier_Record".get_operational_passenger_booking(text,uuid) from public,anon;
revoke all on function "Basic_Carrier_Record".save_operational_passenger_booking(text,uuid,integer,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_operational_passenger_booking(text,uuid) to authenticated;
grant execute on function "Basic_Carrier_Record".save_operational_passenger_booking(text,uuid,integer,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
