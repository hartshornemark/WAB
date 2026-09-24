-- Hold baggage category selection. Existing weights are retained.
-- No active category is inferred for existing records; administrators review and select on next save.
begin;
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights"
add column "Crew_Hold_Baggage_All_Flights" boolean not null default false,
add column "Crew_Hold_Baggage_Longhaul" boolean not null default false,
add column "Crew_Hold_Baggage_Shorthaul" boolean not null default false,
add constraint crew_hold_exclusive check (not ("Crew_Hold_Baggage_All_Flights" and ("Crew_Hold_Baggage_Longhaul" or "Crew_Hold_Baggage_Shorthaul"))),
add constraint crew_hold_all_weights check (not "Crew_Hold_Baggage_All_Flights" or ("Crew_Bag_Weight_FlightDeck_OTHER" is not null and "Crew_Bag_Weight_Cabin_OTHER" is not null)),
add constraint crew_hold_long_weights check (not "Crew_Hold_Baggage_Longhaul" or ("Crew_Bag_Weight_FlightDeck_LHL" is not null and "Crew_Bag_Weight_Cabin_LHL" is not null)),
add constraint crew_hold_short_weights check (not "Crew_Hold_Baggage_Shorthaul" or ("Crew_Bag_Weight_FlightDeck_SHL" is not null and "Crew_Bag_Weight_Cabin_SHL" is not null));
create or replace function "Basic_Carrier_Record".get_carrier_crew_weights(p_iata text) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_can_view boolean := private.can_view_carrier_crew(p_iata); v_raw jsonb; v_xmin text; v_kg boolean; v_lb boolean; v_unit text; v_values jsonb;
begin
if v_can_view then
select to_jsonb(c),c.xmin::text into v_raw,v_xmin from "Basic_Carrier_Record"."Carrier_Crew_Weights" c where "Carrier_IATA"=p_iata;
select "Carrier_Unit_Weight_KG","Carrier_Unit_Weight_LB" into v_kg,v_lb from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata;
end if;
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
'revision',case when v_can_view then md5(coalesce(v_raw::text,'null')||coalesce(v_xmin,'')||coalesce(v_unit,'unset')) else '' end,'unit',v_unit,'values',v_values);
end $$;

create or replace function "Basic_Carrier_Record".save_carrier_crew_weights(p_iata text,p_revision text,p_values jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare v_included boolean; v_all boolean; v_long boolean; v_short boolean; v_key text; v_number text; v_values jsonb := '{}'; v_snapshot jsonb; v_exists boolean; v_required boolean;
begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501'; end if;
if p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'includesHandBaggage') is distinct from 'boolean' then raise exception 'Invalid weights' using errcode='22023'; end if;
v_included := (p_values->>'includesHandBaggage')::boolean;
if jsonb_typeof(p_values->'allFlights') is distinct from 'boolean' or jsonb_typeof(p_values->'longhaul') is distinct from 'boolean' or jsonb_typeof(p_values->'shorthaul') is distinct from 'boolean' then raise exception 'Choose flight categories' using errcode='22023'; end if;
v_all := (p_values->>'allFlights')::boolean; v_long := (p_values->>'longhaul')::boolean; v_short := (p_values->>'shorthaul')::boolean;
if not (v_all or v_long or v_short) or (v_all and (v_long or v_short)) then raise exception 'Choose All Flights or Longhaul and/or Shorthaul' using errcode='22023'; end if;

foreach v_key in array array['flightDeckMale','flightDeckFemale','cabinMale','cabinFemale','flightDeckHand','cabinHand','flightDeckLong','flightDeckShort','flightDeckOther','cabinLong','cabinShort','cabinOther'] loop
v_required := (v_all and v_key in ('flightDeckOther','cabinOther')) or (v_long and v_key in ('flightDeckLong','cabinLong')) or (v_short and v_key in ('flightDeckShort','cabinShort')) or v_key in ('flightDeckMale','flightDeckFemale','cabinMale','cabinFemale') or (not v_included and v_key in ('flightDeckHand','cabinHand'));
if not (p_values ? v_key) then raise exception 'Missing field' using errcode='22023'; end if;
if jsonb_typeof(p_values->v_key)='null' and not v_required then v_values := v_values || jsonb_build_object(v_key,null); continue; end if;
if jsonb_typeof(p_values->v_key) is distinct from 'number' then raise exception 'Weight must be a whole number' using errcode='22023'; end if;
v_number := p_values->>v_key;
if v_number !~ '^[0-9]+$' then raise exception 'Weight must be a nonnegative integer' using errcode='22023'; end if;
if v_number::numeric>2147483647 or (v_key in ('flightDeckMale','flightDeckFemale','cabinMale','cabinFemale') and v_number::numeric<1) then raise exception 'Invalid weight range' using errcode='22023'; end if;
v_values := v_values || jsonb_build_object(v_key,v_number::integer);
end loop;
perform pg_advisory_xact_lock(hashtextextended('carrier-crew:'||p_iata,0));
-- Match the existing details save lock order: basic data before crew data.
perform 1 from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata for update;
perform 1 from "Basic_Carrier_Record"."Carrier_Crew_Weights" where "Carrier_IATA"=p_iata for update;
v_exists := found;
v_snapshot := "Basic_Carrier_Record".get_carrier_crew_weights(p_iata);
if p_revision is distinct from v_snapshot->>'revision' then raise exception 'Weights or unit changed' using errcode='40001'; end if;
if v_snapshot->>'unit' is null then raise exception 'Set the weight unit first' using errcode='22023'; end if;
if v_exists then
update "Basic_Carrier_Record"."Carrier_Crew_Weights" set "Crew_Hold_Baggage_All_Flights"=v_all,"Crew_Hold_Baggage_Longhaul"=v_long,"Crew_Hold_Baggage_Shorthaul"=v_short,"Crew_Weight_Incude_Handbaggage"=v_included,
"Crew_Weight_Flight_Deck_Male"=(v_values->>'flightDeckMale')::integer,
"Crew_Weight_Flight_Deck_Female"=(v_values->>'flightDeckFemale')::integer,
"Crew_Weight_Cabin_Male"=(v_values->>'cabinMale')::integer,
"Crew_Weight_Cabin_Female"=(v_values->>'cabinFemale')::integer,
"Crew_Hand_Bag_Weight_FlightDeck"=(v_values->>'flightDeckHand')::integer,
"Crew_Hand_Bag_Weight_Cabin_Crew"=(v_values->>'cabinHand')::integer,
"Crew_Bag_Weight_FlightDeck_LHL"=(v_values->>'flightDeckLong')::integer,
"Crew_Bag_Weight_FlightDeck_SHL"=(v_values->>'flightDeckShort')::integer,
"Crew_Bag_Weight_FlightDeck_OTHER"=(v_values->>'flightDeckOther')::integer,
"Crew_Bag_Weight_Cabin_LHL"=(v_values->>'cabinLong')::integer,
"Crew_Bag_Weight_Cabin_SHL"=(v_values->>'cabinShort')::integer,
"Crew_Bag_Weight_Cabin_OTHER"=(v_values->>'cabinOther')::integer
where "Carrier_IATA"=p_iata;
else
insert into "Basic_Carrier_Record"."Carrier_Crew_Weights"("Carrier_IATA","Crew_Hold_Baggage_All_Flights","Crew_Hold_Baggage_Longhaul","Crew_Hold_Baggage_Shorthaul","Crew_Weight_Incude_Handbaggage","Crew_Weight_Flight_Deck_Male","Crew_Weight_Flight_Deck_Female","Crew_Weight_Cabin_Male","Crew_Weight_Cabin_Female","Crew_Hand_Bag_Weight_FlightDeck","Crew_Hand_Bag_Weight_Cabin_Crew","Crew_Bag_Weight_FlightDeck_LHL","Crew_Bag_Weight_FlightDeck_SHL","Crew_Bag_Weight_FlightDeck_OTHER","Crew_Bag_Weight_Cabin_LHL","Crew_Bag_Weight_Cabin_SHL","Crew_Bag_Weight_Cabin_OTHER")
values(p_iata,v_all,v_long,v_short,v_included,(v_values->>'flightDeckMale')::integer,(v_values->>'flightDeckFemale')::integer,(v_values->>'cabinMale')::integer,(v_values->>'cabinFemale')::integer,(v_values->>'flightDeckHand')::integer,(v_values->>'cabinHand')::integer,(v_values->>'flightDeckLong')::integer,(v_values->>'flightDeckShort')::integer,(v_values->>'flightDeckOther')::integer,(v_values->>'cabinLong')::integer,(v_values->>'cabinShort')::integer,(v_values->>'cabinOther')::integer);
end if;
return "Basic_Carrier_Record".get_carrier_crew_weights(p_iata);
exception when unique_violation then raise exception 'Weights changed' using errcode='40001';
end $$;
notify pgrst,'reload schema';
commit;
