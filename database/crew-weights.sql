-- B2 API and administrator access. Preserves all existing data and column names.
begin;
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" enable row level security;
revoke all on "Basic_Carrier_Record"."Carrier_Crew_Weights" from public,anon;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_Crew_Weights" to authenticated;
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_flightdeckmale_valid check ("Crew_Weight_Flight_Deck_Male" >= 1);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_flightdeckfemale_valid check ("Crew_Weight_Flight_Deck_Female" >= 1);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_cabinmale_valid check ("Crew_Weight_Cabin_Male" >= 1);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_cabinfemale_valid check ("Crew_Weight_Cabin_Female" >= 1);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_flightdeckhand_valid check ("Crew_Hand_Bag_Weight_FlightDeck" >= 0);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_cabinhand_valid check ("Crew_Hand_Bag_Weight_Cabin_Crew" >= 0);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_flightdecklong_valid check ("Crew_Bag_Weight_FlightDeck_LHL" >= 0);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_flightdeckshort_valid check ("Crew_Bag_Weight_FlightDeck_SHL" >= 0);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_flightdeckother_valid check ("Crew_Bag_Weight_FlightDeck_OTHER" >= 0);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_cabinlong_valid check ("Crew_Bag_Weight_Cabin_LHL" >= 0);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_cabinshort_valid check ("Crew_Bag_Weight_Cabin_SHL" >= 0);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_cabinother_valid check ("Crew_Bag_Weight_Cabin_OTHER" >= 0);
alter table "Basic_Carrier_Record"."Carrier_Crew_Weights" add constraint crew_separate_hand_required check (
"Crew_Weight_Incude_Handbaggage" or ("Crew_Hand_Bag_Weight_FlightDeck" is not null and "Crew_Hand_Bag_Weight_Cabin_Crew" is not null));
create trigger crew_carrier_identifier before update of "Carrier_IATA" on "Basic_Carrier_Record"."Carrier_Crew_Weights" for each row execute function private.protect_carrier_identifier();
create function private.can_view_carrier_crew(p_iata text) returns boolean language sql stable security invoker set search_path='' as $$
select (select auth.uid()) is not null
and exists(select 1 from "Basic_Carrier_Record"."MASTER_Carrier_Contact" where "Carrier_IATA"=p_iata)
and (private.can_edit_carrier_details(p_iata) or private.has_carrier_permission(p_iata,'OPERATING_CONFIG_VIEW'));
$$;
revoke all on function private.can_view_carrier_crew(text) from public,anon;
grant execute on function private.can_view_carrier_crew(text) to authenticated;
alter policy perm_operating_select on "Basic_Carrier_Record"."Carrier_Crew_Weights" to authenticated using (private.can_view_carrier_crew("Carrier_IATA"));
alter policy perm_operating_insert on "Basic_Carrier_Record"."Carrier_Crew_Weights" to authenticated with check (private.can_edit_carrier_details("Carrier_IATA"));
alter policy perm_operating_update on "Basic_Carrier_Record"."Carrier_Crew_Weights" to authenticated using (private.can_edit_carrier_details("Carrier_IATA")) with check (private.can_edit_carrier_details("Carrier_IATA"));
alter policy perm_operating_delete on "Basic_Carrier_Record"."Carrier_Crew_Weights" to authenticated using (private.can_edit_carrier_details("Carrier_IATA"));

create function "Basic_Carrier_Record".get_carrier_crew_weights(p_iata text) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_can_view boolean := private.can_view_carrier_crew(p_iata); v_raw jsonb; v_xmin text; v_kg boolean; v_lb boolean; v_unit text; v_values jsonb;
begin
if v_can_view then
select to_jsonb(c),c.xmin::text into v_raw,v_xmin from "Basic_Carrier_Record"."Carrier_Crew_Weights" c where "Carrier_IATA"=p_iata;
select "Carrier_Unit_Weight_KG","Carrier_Unit_Weight_LB" into v_kg,v_lb from "Basic_Carrier_Record"."Basic_Carrier_Data" where "Carrier_IATA"=p_iata;
end if;
v_unit := case when v_kg and not v_lb then 'KG' when v_lb and not v_kg then 'LB' else null end;
v_values := jsonb_build_object('includesHandBaggage',coalesce(v_raw->'Crew_Weight_Incude_Handbaggage','true'::jsonb),
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

create function "Basic_Carrier_Record".save_carrier_crew_weights(p_iata text,p_revision text,p_values jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare v_included boolean; v_key text; v_number text; v_values jsonb := '{}'; v_snapshot jsonb; v_exists boolean; v_required boolean;
begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501'; end if;
if p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'includesHandBaggage') is distinct from 'boolean' then raise exception 'Invalid weights' using errcode='22023'; end if;
v_included := (p_values->>'includesHandBaggage')::boolean;
foreach v_key in array array['flightDeckMale','flightDeckFemale','cabinMale','cabinFemale','flightDeckHand','cabinHand','flightDeckLong','flightDeckShort','flightDeckOther','cabinLong','cabinShort','cabinOther'] loop
v_required := v_key in ('flightDeckMale','flightDeckFemale','cabinMale','cabinFemale') or (not v_included and v_key in ('flightDeckHand','cabinHand'));
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
update "Basic_Carrier_Record"."Carrier_Crew_Weights" set "Crew_Weight_Incude_Handbaggage"=v_included,
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
insert into "Basic_Carrier_Record"."Carrier_Crew_Weights"("Carrier_IATA","Crew_Weight_Incude_Handbaggage","Crew_Weight_Flight_Deck_Male","Crew_Weight_Flight_Deck_Female","Crew_Weight_Cabin_Male","Crew_Weight_Cabin_Female","Crew_Hand_Bag_Weight_FlightDeck","Crew_Hand_Bag_Weight_Cabin_Crew","Crew_Bag_Weight_FlightDeck_LHL","Crew_Bag_Weight_FlightDeck_SHL","Crew_Bag_Weight_FlightDeck_OTHER","Crew_Bag_Weight_Cabin_LHL","Crew_Bag_Weight_Cabin_SHL","Crew_Bag_Weight_Cabin_OTHER")
values(p_iata,v_included,(v_values->>'flightDeckMale')::integer,(v_values->>'flightDeckFemale')::integer,(v_values->>'cabinMale')::integer,(v_values->>'cabinFemale')::integer,(v_values->>'flightDeckHand')::integer,(v_values->>'cabinHand')::integer,(v_values->>'flightDeckLong')::integer,(v_values->>'flightDeckShort')::integer,(v_values->>'flightDeckOther')::integer,(v_values->>'cabinLong')::integer,(v_values->>'cabinShort')::integer,(v_values->>'cabinOther')::integer);
end if;
return "Basic_Carrier_Record".get_carrier_crew_weights(p_iata);
exception when unique_violation then raise exception 'Weights changed' using errcode='40001';
end $$;
revoke all on function "Basic_Carrier_Record".get_carrier_crew_weights(text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_carrier_crew_weights(text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_carrier_crew_weights(text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_carrier_crew_weights(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
