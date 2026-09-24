begin;
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes"
  add column if not exists "Flight_Deck_Baggage_Location" varchar(1),
  add column if not exists "Cabin_Crew_Baggage_Location" varchar(1);
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" drop constraint if exists "Aircraft_Crew_Codes_Flight_Deck_Baggage_Hold_fkey";
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" add constraint "Aircraft_Crew_Codes_Flight_Deck_Baggage_Hold_fkey"
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Flight_Deck_Baggage_Location","Aircraft_Series_Subtype")
  references "Basic_Carrier_Record"."Aircraft_Holds"("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
  on update cascade on delete restrict;
create index if not exists "Aircraft_Crew_Codes_Flight_Deck_Baggage_Hold_idx" on "Basic_Carrier_Record"."Aircraft_Crew_Codes"("Carrier_IATA","Aircraft_Type_IATA","Flight_Deck_Baggage_Location","Aircraft_Series_Subtype") where "Flight_Deck_Baggage_Location" is not null;
create index if not exists "Aircraft_Crew_Codes_Cabin_Crew_Baggage_Hold_idx" on "Basic_Carrier_Record"."Aircraft_Crew_Codes"("Carrier_IATA","Aircraft_Type_IATA","Cabin_Crew_Baggage_Location","Aircraft_Series_Subtype") where "Cabin_Crew_Baggage_Location" is not null;
drop policy if exists e2_global_select on "Basic_Carrier_Record"."Aircraft_Crew_Codes";
create policy e2_global_select on "Basic_Carrier_Record"."Aircraft_Crew_Codes" for select to authenticated using ((select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
drop policy if exists e2_global_insert on "Basic_Carrier_Record"."Aircraft_Crew_Codes";
create policy e2_global_insert on "Basic_Carrier_Record"."Aircraft_Crew_Codes" for insert to authenticated with check ((select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
drop policy if exists e2_global_update on "Basic_Carrier_Record"."Aircraft_Crew_Codes";
create policy e2_global_update on "Basic_Carrier_Record"."Aircraft_Crew_Codes" for update to authenticated using ((select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
drop policy if exists e2_global_delete on "Basic_Carrier_Record"."Aircraft_Crew_Codes";
create policy e2_global_delete on "Basic_Carrier_Record"."Aircraft_Crew_Codes" for delete to authenticated using ((select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
drop policy if exists e2_global_select on "Basic_Carrier_Record"."Aircraft_Pantry_Codes";
create policy e2_global_select on "Basic_Carrier_Record"."Aircraft_Pantry_Codes" for select to authenticated using ((select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
drop policy if exists e2_global_insert on "Basic_Carrier_Record"."Aircraft_Pantry_Codes";
create policy e2_global_insert on "Basic_Carrier_Record"."Aircraft_Pantry_Codes" for insert to authenticated with check ((select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
drop policy if exists e2_global_update on "Basic_Carrier_Record"."Aircraft_Pantry_Codes";
create policy e2_global_update on "Basic_Carrier_Record"."Aircraft_Pantry_Codes" for update to authenticated using ((select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
drop policy if exists e2_global_delete on "Basic_Carrier_Record"."Aircraft_Pantry_Codes";
create policy e2_global_delete on "Basic_Carrier_Record"."Aircraft_Pantry_Codes" for delete to authenticated using ((select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
drop policy if exists e2_global_select on "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations";
create policy e2_global_select on "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations" for select to authenticated using ((select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
drop policy if exists e2_global_select on "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations";
create policy e2_global_select on "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations" for select to authenticated using ((select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" drop constraint if exists "Aircraft_Crew_Codes_Cabin_Crew_Baggage_Hold_fkey";
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" add constraint "Aircraft_Crew_Codes_Cabin_Crew_Baggage_Hold_fkey"
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Cabin_Crew_Baggage_Location","Aircraft_Series_Subtype")
  references "Basic_Carrier_Record"."Aircraft_Holds"("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
  on update cascade on delete restrict;
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" drop constraint if exists "Aircraft_Crew_Codes_Seat_Counts_check";
alter table "Basic_Carrier_Record"."Aircraft_Crew_Codes" add constraint "Aircraft_Crew_Codes_Seat_Counts_check" check ("Flight_Deck_Seats_Occupied">=0 and "Cabin_Crew_Seats_Occupied">=0);

-- E2 is the source of the actual crew codes used by E4. Keep the compact
-- definition table in sync because E4's configuration table references it.
create or replace function private.ensure_aircraft_crew_code_definition()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  insert into "Basic_Carrier_Record"."Aircraft_Crew_Code_Definitions"(
    "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID"
  ) values (
    new."Carrier_IATA",new."Aircraft_Type_IATA",new."Aircraft_Series_Subtype",new."Crew_Code_ID"
  ) on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID") do nothing;
  return new;
end $$;
revoke all on function private.ensure_aircraft_crew_code_definition() from public,anon,authenticated;
drop trigger if exists ensure_aircraft_crew_code_definition on "Basic_Carrier_Record"."Aircraft_Crew_Codes";
create trigger ensure_aircraft_crew_code_definition
before insert on "Basic_Carrier_Record"."Aircraft_Crew_Codes"
for each row execute function private.ensure_aircraft_crew_code_definition();

insert into "Basic_Carrier_Record"."Aircraft_Crew_Code_Definitions"(
  "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID"
)
select distinct "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID"
from "Basic_Carrier_Record"."Aircraft_Crew_Codes"
on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID") do nothing;
alter table "Basic_Carrier_Record"."Aircraft_Pantry_Codes" drop constraint if exists "Aircraft_Pantry_Codes_Values_check";
alter table "Basic_Carrier_Record"."Aircraft_Pantry_Codes" add constraint "Aircraft_Pantry_Codes_Values_check" check ("Pantry_Total_Weight">=0 and abs("Pantry_BA")<=1000000000 and "Pantry_Index" is not null and abs("Pantry_Index")<=1000000000 and nullif(btrim("Pantry_Galley_Locations"::text),'') is not null);

create or replace function "Basic_Carrier_Record".get_aircraft_e2(p_iata text,p_type_code text,p_subtype text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; can_view boolean; can_edit boolean; revision text;
begin
  can_view:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW');
  can_edit:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  select md5(coalesce(jsonb_agg(x order by x::text)::text,'[]')) into revision from (
    select to_jsonb(c) x from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=p_type_code and c."Aircraft_Series_Subtype"=p_subtype
    union all select to_jsonb(p) from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=p_type_code and p."Aircraft_Series_Subtype"=p_subtype
  ) q;
  result:=jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',revision,'typeCode',p_type_code,'subtype',p_subtype,
    'crewRows',coalesce((select jsonb_agg(jsonb_build_object('crewCode',btrim(c."Crew_Code_ID"::text),'flightDeckLocationId',btrim(c."Flight_Deck_Location_Short_Form_ID"::text),'flightDeckSeats',c."Flight_Deck_Seats_Occupied",'cabinCrewLocationId',btrim(c."Cabin_Crew_Location_Short_Form_ID"::text),'cabinCrewSeats',c."Cabin_Crew_Seats_Occupied",'flightDeckBaggageLocation',c."Flight_Deck_Baggage_Location",'cabinCrewBaggageLocation',c."Cabin_Crew_Baggage_Location") order by c."Crew_Code_ID",c."Flight_Deck_Location_Short_Form_ID",c."Cabin_Crew_Location_Short_Form_ID") from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=p_type_code and c."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb),
    'pantryRows',coalesce((select jsonb_agg(jsonb_build_object('pantryCode',btrim(p."Pantry_Code_ID"::text),'galleyLocations',btrim(p."Pantry_Galley_Locations"::text),'totalWeight',p."Pantry_Total_Weight",'balanceArm',p."Pantry_BA",'index',p."Pantry_Index") order by p."Pantry_Code_ID") from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=p_type_code and p."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb),
    'flightDeckLocations',coalesce((select jsonb_agg(jsonb_build_object('id',btrim(l."Location_Short_Form_ID"::text),'description',l."Location_Description") order by l."Location_Short_Form_ID") from "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations" l where l."Carrier_IATA"=p_iata and l."Aircraft_Type_IATA"=p_type_code and l."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb),
    'cabinCrewLocations',coalesce((select jsonb_agg(jsonb_build_object('id',btrim(l."Location_Short_Form_ID"::text),'description',l."Location_Description") order by l."Location_Short_Form_ID") from "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations" l where l."Carrier_IATA"=p_iata and l."Aircraft_Type_IATA"=p_type_code and l."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb),
    'holds',coalesce((select jsonb_agg(jsonb_build_object('id',btrim(h."Hold_Name_ID"::text),'description','Hold '||btrim(h."Hold_Name_ID"::text)) order by h."Hold_Name_ID") from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=p_type_code and h."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb));
  return result;
end$$;

create or replace function "Basic_Carrier_Record".save_aircraft_e2_crew(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare row_data jsonb; current_revision text;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  current_revision:="Basic_Carrier_Record".get_aircraft_e2(p_iata,p_type_code,p_subtype)->>'revision';if current_revision<>p_revision then raise exception 'Revision conflict' using errcode='40001';end if;
  delete from "Basic_Carrier_Record"."Aircraft_Crew_Codes" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type_code and "Aircraft_Series_Subtype"=p_subtype;
  for row_data in select value from jsonb_array_elements(p_rows) loop
    insert into "Basic_Carrier_Record"."Aircraft_Crew_Codes"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Flight_Deck_Location_Short_Form_ID","Flight_Deck_Seats_Occupied","Cabin_Crew_Location_Short_Form_ID","Cabin_Crew_Seats_Occupied","Flight_Deck_Baggage_Location","Cabin_Crew_Baggage_Location")
    values(p_iata,p_type_code,p_subtype,row_data->>'crewCode',row_data->>'flightDeckLocationId',(row_data->>'flightDeckSeats')::integer,row_data->>'cabinCrewLocationId',(row_data->>'cabinCrewSeats')::integer,nullif(row_data->>'flightDeckBaggageLocation',''),nullif(row_data->>'cabinCrewBaggageLocation',''));
  end loop;return "Basic_Carrier_Record".get_aircraft_e2(p_iata,p_type_code,p_subtype);
end$$;

create or replace function "Basic_Carrier_Record".save_aircraft_e2_pantry(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare row_data jsonb; current_revision text;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  current_revision:="Basic_Carrier_Record".get_aircraft_e2(p_iata,p_type_code,p_subtype)->>'revision';if current_revision<>p_revision then raise exception 'Revision conflict' using errcode='40001';end if;
  delete from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type_code and "Aircraft_Series_Subtype"=p_subtype;
  for row_data in select value from jsonb_array_elements(p_rows) loop
    insert into "Basic_Carrier_Record"."Aircraft_Pantry_Codes"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Pantry_Code_ID","Pantry_Galley_Locations","Pantry_Total_Weight","Pantry_BA","Pantry_Index")
    values(p_iata,p_type_code,p_subtype,row_data->>'pantryCode',row_data->>'galleyLocations',(row_data->>'totalWeight')::integer,(row_data->>'balanceArm')::double precision,(row_data->>'index')::double precision);
  end loop;return "Basic_Carrier_Record".get_aircraft_e2(p_iata,p_type_code,p_subtype);
end$$;
revoke all on function "Basic_Carrier_Record".get_aircraft_e2(text,text,text) from public,anon;grant execute on function "Basic_Carrier_Record".get_aircraft_e2(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_e2_crew(text,text,text,text,jsonb) from public,anon;grant execute on function "Basic_Carrier_Record".save_aircraft_e2_crew(text,text,text,text,jsonb) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_e2_pantry(text,text,text,text,jsonb) from public,anon;grant execute on function "Basic_Carrier_Record".save_aircraft_e2_pantry(text,text,text,text,jsonb) to authenticated;
commit;
