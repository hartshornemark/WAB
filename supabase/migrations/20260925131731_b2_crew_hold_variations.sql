begin;
create table "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" (
 "ID" uuid primary key default gen_random_uuid(),
 "Carrier_IATA" varchar(2) not null references "Basic_Carrier_Record"."Basic_Carrier_Data"("Carrier_IATA"),
 "Variation_Code" text,
 "Mode" text not null check ("Mode" in ('STANDARD','SEPARATE')),
 "Flight_Deck_Weight" integer check ("Flight_Deck_Weight">=0),
 "Cabin_Weight" integer check ("Cabin_Weight">=0),
 unique nulls not distinct ("Carrier_IATA","Variation_Code"),
 foreign key ("Variation_Code","Carrier_IATA") references "Basic_Carrier_Record"."Carrier_Flight_Variations"("Flight_Type_Variation","Carrier_IATA") on delete cascade,
 check (("Variation_Code" is not null or "Mode"='SEPARATE') and ("Mode"='STANDARD' or ("Flight_Deck_Weight" is not null and "Cabin_Weight" is not null)))
);
comment on table "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" is 'B2 reviewed Standard and Flight Variation crew hold baggage weights per crew member. NULL variation is Standard.';
alter table "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" from anon;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" to authenticated;
create policy crew_hold_read on "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" for select to authenticated using(private.can_view_carrier_crew("Carrier_IATA"));
create policy crew_hold_insert on "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" for insert to authenticated with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy crew_hold_update on "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" for update to authenticated using(private.can_edit_carrier_details("Carrier_IATA")) with check(private.can_edit_carrier_details("Carrier_IATA"));
create policy crew_hold_delete on "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" for delete to authenticated using(private.can_edit_carrier_details("Carrier_IATA"));
-- Preserve reviewed All Flights weights and their coverage of existing variations.
insert into "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage"("Carrier_IATA","Mode","Flight_Deck_Weight","Cabin_Weight")
select "Carrier_IATA",'SEPARATE',"Crew_Bag_Weight_FlightDeck_OTHER","Crew_Bag_Weight_Cabin_OTHER" from "Basic_Carrier_Record"."Carrier_Crew_Weights" where "Crew_Hold_Baggage_All_Flights" and "Crew_Bag_Weight_FlightDeck_OTHER" is not null and "Crew_Bag_Weight_Cabin_OTHER" is not null;
insert into "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage"("Carrier_IATA","Variation_Code","Mode") select v."Carrier_IATA",v."Flight_Type_Variation",'STANDARD' from "Basic_Carrier_Record"."Carrier_Flight_Variations" v join "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" h on h."Carrier_IATA"=v."Carrier_IATA" and h."Variation_Code" is null;
-- Legacy selected Longhaul/Shorthaul become ordinary carrier variations.
insert into "Basic_Carrier_Record"."Carrier_Flight_Variations"("Carrier_IATA","Flight_Type_Variation","Flight_Type_Variation_Description")
select "Carrier_IATA",'LHL','Longhaul' from "Basic_Carrier_Record"."Carrier_Crew_Weights" where "Crew_Hold_Baggage_Longhaul" union all select "Carrier_IATA",'SHL','Shorthaul' from "Basic_Carrier_Record"."Carrier_Crew_Weights" where "Crew_Hold_Baggage_Shorthaul" on conflict do nothing;
insert into "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage"("Carrier_IATA","Variation_Code","Mode","Flight_Deck_Weight","Cabin_Weight")
select "Carrier_IATA",'LHL','SEPARATE',"Crew_Bag_Weight_FlightDeck_LHL","Crew_Bag_Weight_Cabin_LHL" from "Basic_Carrier_Record"."Carrier_Crew_Weights" where "Crew_Hold_Baggage_Longhaul" and "Crew_Bag_Weight_FlightDeck_LHL" is not null and "Crew_Bag_Weight_Cabin_LHL" is not null
union all select "Carrier_IATA",'SHL','SEPARATE',"Crew_Bag_Weight_FlightDeck_SHL","Crew_Bag_Weight_Cabin_SHL" from "Basic_Carrier_Record"."Carrier_Crew_Weights" where "Crew_Hold_Baggage_Shorthaul" and "Crew_Bag_Weight_FlightDeck_SHL" is not null and "Crew_Bag_Weight_Cabin_SHL" is not null
on conflict ("Carrier_IATA","Variation_Code") do update set "Mode"=excluded."Mode","Flight_Deck_Weight"=excluded."Flight_Deck_Weight","Cabin_Weight"=excluded."Cabin_Weight";
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".get_carrier_crew_weights(p_iata text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_can_view boolean := private.can_view_carrier_crew(p_iata); v_raw jsonb; v_xmin text; v_kg boolean; v_lb boolean; v_unit text; v_values jsonb; hold_rows jsonb; variations jsonb;
begin
if v_can_view then
select to_jsonb(c),c.xmin::text into v_raw,v_xmin from "Basic_Carrier_Record"."Carrier_Crew_Weights" c where "Carrier_IATA"=p_iata;
select "Carrier_Unit_Weight_KG","Carrier_Unit_Weight_LB" into v_kg,v_lb from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata;
end if;
if v_can_view then
select coalesce(jsonb_agg(jsonb_build_object('code',"Variation_Code",'mode',"Mode",'flightDeck',"Flight_Deck_Weight",'cabin',"Cabin_Weight") order by "Variation_Code" nulls first),'[]') into hold_rows from "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage" where "Carrier_IATA"=p_iata;
select coalesce(jsonb_agg(jsonb_build_object('code',"Flight_Type_Variation",'description',"Flight_Type_Variation_Description") order by "Flight_Type_Variation"),'[]') into variations from "Basic_Carrier_Record"."Carrier_Flight_Variations" where "Carrier_IATA"=p_iata;
else hold_rows:='[]';variations:='[]';end if;
v_unit := case when v_kg and not v_lb then 'KG' when v_lb and not v_kg then 'LB' else null end;
v_values := jsonb_build_object('allFlights',coalesce(v_raw->'Crew_Hold_Baggage_All_Flights','false'::jsonb),'longhaul',coalesce(v_raw->'Crew_Hold_Baggage_Longhaul','false'::jsonb),'shorthaul',coalesce(v_raw->'Crew_Hold_Baggage_Shorthaul','false'::jsonb),'includesHandBaggage',coalesce(v_raw->'Crew_Weight_Incude_Handbaggage','true'::jsonb),
'flightDeckMale',v_raw->'Crew_Weight_Flight_Deck_Male',
'flightDeckFemale',v_raw->'Crew_Weight_Flight_Deck_Female',
'cabinMale',v_raw->'Crew_Weight_Cabin_Male',
'cabinFemale',v_raw->'Crew_Weight_Cabin_Female',
'flightDeckHand',v_raw->'Crew_Hand_Bag_Weight_FlightDeck',
'cabinHand',v_raw->'Crew_Hand_Bag_Weight_Cabin_Crew',
'flightDeckLong',v_raw->'Crew_Bag_Weight_FlightDeck_LHL',
'flightDeckShort',v_raw->'Crew_Bag_Weight_FlightDeck_SHL',
'flightDeckOther',v_raw->'Crew_Bag_Weight_FlightDeck_OTHER',
'cabinLong',v_raw->'Crew_Bag_Weight_Cabin_LHL',
'cabinShort',v_raw->'Crew_Bag_Weight_Cabin_SHL',
'cabinOther',v_raw->'Crew_Bag_Weight_Cabin_OTHER');
return jsonb_build_object('canView',v_can_view,'canEdit',v_can_view and private.can_edit_carrier_details(p_iata),'exists',v_raw is not null,
'revision',case when v_can_view then md5(coalesce(v_raw::text,'null')||coalesce(v_xmin,'')||coalesce(v_unit,'unset')||hold_rows::text||variations::text) else '' end,'unit',v_unit,'values',v_values,'holdRows',hold_rows,'variations',variations);
end $function$

;
create function "Basic_Carrier_Record".save_carrier_crew_hold_baggage(p_iata text,p_revision text,p_code text,p_values jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare s jsonb; m text:=p_values->>'mode'; fd integer; cc integer; k text;
begin
 if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('carrier-crew:'||p_iata,0));
 perform 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata for update;
 s:="Basic_Carrier_Record".get_carrier_crew_weights(p_iata);
 if p_revision is distinct from s->>'revision' then raise exception 'Weights changed' using errcode='40001';end if;
 if s->>'unit' is null then raise exception 'Set the B1 weight unit first' using errcode='22023';end if;
 if p_code is not null and not exists(select 1 from "Basic_Carrier_Record"."Carrier_Flight_Variations" where "Carrier_IATA"=p_iata and "Flight_Type_Variation"=p_code) then raise exception 'Variation missing' using errcode='23503';end if;
 if m is null or m not in ('STANDARD','SEPARATE') or (p_code is null and m<>'SEPARATE') then raise exception 'Invalid mode' using errcode='22023';end if;
 if m='SEPARATE' then
 foreach k in array array['flightDeck','cabin'] loop
 if jsonb_typeof(p_values->k) is distinct from 'number' or (p_values->>k) !~ '^[0-9]+$' or (p_values->>k)::numeric>2147483647 then raise exception 'Enter both nonnegative whole weights' using errcode='22023';end if;
 end loop;
 fd:=(p_values->>'flightDeck')::integer;cc:=(p_values->>'cabin')::integer;
 end if;
 insert into "Basic_Carrier_Record"."Carrier_Crew_Hold_Baggage"("Carrier_IATA","Variation_Code","Mode","Flight_Deck_Weight","Cabin_Weight") values(p_iata,p_code,m,fd,cc)
 on conflict ("Carrier_IATA","Variation_Code") do update set "Mode"=excluded."Mode","Flight_Deck_Weight"=coalesce(excluded."Flight_Deck_Weight","Carrier_Crew_Hold_Baggage"."Flight_Deck_Weight"),"Cabin_Weight"=coalesce(excluded."Cabin_Weight","Carrier_Crew_Hold_Baggage"."Cabin_Weight");
 return "Basic_Carrier_Record".get_carrier_crew_weights(p_iata);
end $$;
revoke all on function "Basic_Carrier_Record".save_carrier_crew_hold_baggage(text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_carrier_crew_hold_baggage(text,text,text,jsonb) to authenticated;
commit;
