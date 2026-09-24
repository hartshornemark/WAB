-- Run after crew-hold-selection.sql. All changes are rolled back.
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"b5c937a4-db85-4b47-bb59-23c99cc6799d","role":"authenticated"}',true);
do $$ declare s jsonb; t jsonb; v jsonb; invalid jsonb; begin
s:="Basic_Carrier_Record".get_carrier_crew_weights('ZZ');
v := (s->'values') || '{"allFlights":true,"longhaul":false,"shorthaul":false,"flightDeckOther":12,"cabinOther":10,"flightDeckLong":20,"cabinLong":18,"flightDeckShort":8,"cabinShort":6}'::jsonb;
t:="Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',v);
if t->'values'<>v then raise exception 'FAIL all-flights round trip'; end if;
s:=t;
for invalid in select value from jsonb_array_elements('[{"longhaul":true},{"shorthaul":true},{"allFlights":false},{"allFlights":"true"},{"flightDeckOther":null},{"cabinOther":null}]') loop
begin perform "Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',(s->'values')||invalid); raise exception 'FAIL invalid category selection accepted %',invalid; exception when invalid_parameter_value then null; end;
end loop;
v:=(s->'values') || '{"allFlights":false,"longhaul":true,"shorthaul":true}'::jsonb;
t:="Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',v);
if t->'values'<>v or t->'values'->>'flightDeckOther'<>'12' then raise exception 'FAIL specific flights and retained inactive weights'; end if;
s:=t; v:=(s->'values')||'{"shorthaul":false}'::jsonb;
t:="Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',v);
if (t->'values'->>'shorthaul')::boolean then raise exception 'FAIL longhaul alone'; end if;
s:=t; v:=(s->'values')||'{"longhaul":false,"shorthaul":true}'::jsonb;
t:="Basic_Carrier_Record".save_carrier_crew_weights('ZZ',s->>'revision',v);
if (t->'values'->>'longhaul')::boolean or not (t->'values'->>'shorthaul')::boolean then raise exception 'FAIL shorthaul alone'; end if;
begin update "Basic_Carrier_Record"."Carrier_Crew_Weights" set "Crew_Hold_Baggage_All_Flights"=true where "Carrier_IATA"='ZZ'; raise exception 'FAIL direct conflicting categories'; exception when check_violation then null; end;
begin update "Basic_Carrier_Record"."Carrier_Crew_Weights" set "Crew_Bag_Weight_Cabin_SHL"=null where "Carrier_IATA"='ZZ'; raise exception 'FAIL direct missing active weight'; exception when check_violation then null; end;
end $$;
reset role;
select 'PASS exclusive category choices, required active weights, independent longhaul/shorthaul, retained inactive weights and direct constraints' as result;
rollback;
