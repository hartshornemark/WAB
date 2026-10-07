begin;

alter table "Basic_Carrier_Record"."Aircraft_Pantry_Codes"
  add column if not exists "DOW_Adjustment_Method" varchar(12) not null default 'BY_GALLEY';
alter table "Basic_Carrier_Record"."Aircraft_Pantry_Codes" drop constraint if exists "Aircraft_Pantry_Codes_DOW_Adjustment_Method_check";
alter table "Basic_Carrier_Record"."Aircraft_Pantry_Codes" add constraint "Aircraft_Pantry_Codes_DOW_Adjustment_Method_check" check ("DOW_Adjustment_Method" in ('ONE_LINE','BY_GALLEY') and (not "Is_DOW_Base" or "DOW_Adjustment_Method"='BY_GALLEY'));

create or replace function "Basic_Carrier_Record".get_aircraft_e2(p_iata text,p_type_code text,p_subtype text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb; can_view boolean; can_edit boolean; revision text; principle text;
begin
  can_view:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW');
  can_edit:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  select "Start_Weight_Principle" into principle from "Basic_Carrier_Record"."Basic_Aircraft_Data"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type_code and "Aircraft_Series_Subtype"=p_subtype;
  select md5(coalesce(jsonb_agg(x order by x::text)::text,'[]')||coalesce(principle,'')) into revision from (
    select to_jsonb(c) x from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=p_type_code and c."Aircraft_Series_Subtype"=p_subtype
    union all select to_jsonb(p) from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=p_type_code and p."Aircraft_Series_Subtype"=p_subtype
  ) q;
  result:=jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',revision,'typeCode',p_type_code,'subtype',p_subtype,'startWeightPrinciple',principle,
    'crewRows',coalesce((select jsonb_agg(jsonb_build_object('crewCode',btrim(c."Crew_Code_ID"::text),'flightDeckLocationId',btrim(c."Flight_Deck_Location_Short_Form_ID"::text),'flightDeckSeats',c."Flight_Deck_Seats_Occupied",'cabinCrewLocationId',coalesce(btrim(c."Cabin_Crew_Location_Short_Form_ID"::text),''),'cabinCrewSeats',c."Cabin_Crew_Seats_Occupied",'flightDeckBaggageLocation',c."Flight_Deck_Baggage_Location",'cabinCrewBaggageLocation',c."Cabin_Crew_Baggage_Location",'isBase',c."Is_DOW_Base",'weightAdjustment',c."DOW_Weight_Adjustment",'indexAdjustment',c."DOI_Adjustment") order by c."Crew_Code_ID",c."Flight_Deck_Location_Short_Form_ID",c."Cabin_Crew_Location_Short_Form_ID") from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=p_type_code and c."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb),
    'pantryRows',coalesce((select jsonb_agg(jsonb_build_object('pantryCode',btrim(p."Pantry_Code_ID"::text),'adjustmentMethod',p."DOW_Adjustment_Method",'galleyLocations',btrim(p."Pantry_Galley_Locations"::text),'totalWeight',p."Pantry_Total_Weight",'balanceArm',p."Pantry_BA",'index',p."Pantry_Index",'isBase',p."Is_DOW_Base",'weightAdjustment',p."DOW_Weight_Adjustment",'indexAdjustment',p."DOI_Adjustment") order by p."Pantry_Code_ID") from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=p_type_code and p."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb),
    'flightDeckLocations',coalesce((select jsonb_agg(jsonb_build_object('id',btrim(l."Location_Short_Form_ID"::text),'description',l."Location_Description") order by l."Location_Short_Form_ID") from "Basic_Carrier_Record"."Aircraft_Flight_Deck_Locations" l where l."Carrier_IATA"=p_iata and l."Aircraft_Type_IATA"=p_type_code and l."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb),
    'cabinCrewLocations',coalesce((select jsonb_agg(jsonb_build_object('id',btrim(l."Location_Short_Form_ID"::text),'description',l."Location_Description") order by l."Location_Short_Form_ID") from "Basic_Carrier_Record"."Aircraft_Cabin_Crew_Locations" l where l."Carrier_IATA"=p_iata and l."Aircraft_Type_IATA"=p_type_code and l."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb),
    'holds',coalesce((select jsonb_agg(jsonb_build_object('id',btrim(h."Hold_Name_ID"::text),'description','Hold '||btrim(h."Hold_Name_ID"::text)) order by h."Hold_Name_ID") from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=p_type_code and h."Aircraft_Series_Subtype"=p_subtype),'[]'::jsonb));
  return result;
end$$;

create or replace function "Basic_Carrier_Record".save_aircraft_e2_pantry(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare row_data jsonb; current_revision text; principle text;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  current_revision:="Basic_Carrier_Record".get_aircraft_e2(p_iata,p_type_code,p_subtype)->>'revision';if current_revision<>p_revision then raise exception 'Revision conflict' using errcode='40001';end if;
  select "Start_Weight_Principle" into principle from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type_code and "Aircraft_Series_Subtype"=p_subtype;
  if principle='DRY_OPERATING_WEIGHT' then
    if exists(select 1 from jsonb_array_elements(p_rows) r where coalesce(r->>'adjustmentMethod','BY_GALLEY') not in ('ONE_LINE','BY_GALLEY')) then raise exception 'Select ALL GALLEYS or BY GALLEY for every pantry code' using errcode='23514'; end if;
    if exists(select 1 from jsonb_array_elements(p_rows) r where coalesce((r->>'isBase')::boolean,false) and coalesce(r->>'adjustmentMethod','BY_GALLEY')<>'BY_GALLEY') then raise exception 'The base pantry code must use BY GALLEY' using errcode='23514'; end if;
    if (select count(*) from jsonb_array_elements(p_rows) r where coalesce((r->>'isBase')::boolean,false))<>1 then raise exception 'Select exactly one base pantry code' using errcode='23514'; end if;
    if exists(select 1 from jsonb_array_elements(p_rows) r where jsonb_typeof(r->'weightAdjustment')<>'number' or jsonb_typeof(r->'indexAdjustment')<>'number') then raise exception 'Enter every pantry DOW and DOI adjustment' using errcode='23514'; end if;
    if exists(select 1 from jsonb_array_elements(p_rows) r where coalesce((r->>'isBase')::boolean,false) and ((r->>'weightAdjustment')::numeric<>0 or (r->>'indexAdjustment')::numeric<>0)) then raise exception 'Base pantry adjustments must be zero' using errcode='23514'; end if;
  end if;
  delete from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type_code and "Aircraft_Series_Subtype"=p_subtype;
  for row_data in select value from jsonb_array_elements(p_rows) loop
    insert into "Basic_Carrier_Record"."Aircraft_Pantry_Codes"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Pantry_Code_ID","Pantry_Galley_Locations","Pantry_Total_Weight","Pantry_BA","Pantry_Index","DOW_Adjustment_Method","Is_DOW_Base","DOW_Weight_Adjustment","DOI_Adjustment")
    values(p_iata,p_type_code,p_subtype,row_data->>'pantryCode',case when principle='DRY_OPERATING_WEIGHT' and coalesce(row_data->>'adjustmentMethod','BY_GALLEY')='ONE_LINE' then 'ALL' else row_data->>'galleyLocations' end,case when principle='DRY_OPERATING_WEIGHT' and coalesce(row_data->>'adjustmentMethod','BY_GALLEY')='ONE_LINE' then 0 else (row_data->>'totalWeight')::integer end,case when principle='DRY_OPERATING_WEIGHT' and coalesce(row_data->>'adjustmentMethod','BY_GALLEY')='ONE_LINE' then 0 else (row_data->>'balanceArm')::double precision end,case when principle='DRY_OPERATING_WEIGHT' and coalesce(row_data->>'adjustmentMethod','BY_GALLEY')='ONE_LINE' then 0 else (row_data->>'index')::double precision end,case when principle='DRY_OPERATING_WEIGHT' then coalesce(row_data->>'adjustmentMethod','BY_GALLEY') else 'BY_GALLEY' end,case when principle='DRY_OPERATING_WEIGHT' then coalesce((row_data->>'isBase')::boolean,false) else false end,case when principle='DRY_OPERATING_WEIGHT' then (row_data->>'weightAdjustment')::integer else null end,case when principle='DRY_OPERATING_WEIGHT' then (row_data->>'indexAdjustment')::double precision else null end);
  end loop;return "Basic_Carrier_Record".get_aircraft_e2(p_iata,p_type_code,p_subtype);
end$$;

revoke all on function "Basic_Carrier_Record".get_aircraft_e2(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_e2(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_e2_pantry(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_e2_pantry(text,text,text,text,jsonb) to authenticated;

commit;
