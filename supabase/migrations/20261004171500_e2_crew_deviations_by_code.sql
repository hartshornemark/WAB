begin;

drop index if exists "Basic_Carrier_Record"."Aircraft_Crew_Codes_one_DOW_base";
create index if not exists "Aircraft_Crew_Codes_DOW_base_idx"
  on "Basic_Carrier_Record"."Aircraft_Crew_Codes"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
  where "Is_DOW_Base";

with chosen as (
  select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",min("Crew_Code_ID") filter (where "Is_DOW_Base") "Crew_Code_ID"
  from "Basic_Carrier_Record"."Aircraft_Crew_Codes"
  group by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"
)
update "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
set "Is_DOW_Base"=true,"DOW_Weight_Adjustment"=0,"DOI_Adjustment"=0
from chosen b
where b."Crew_Code_ID" is not null and c."Carrier_IATA"=b."Carrier_IATA" and c."Aircraft_Type_IATA"=b."Aircraft_Type_IATA"
  and c."Aircraft_Series_Subtype"=b."Aircraft_Series_Subtype" and c."Crew_Code_ID"=b."Crew_Code_ID";

create or replace function "Basic_Carrier_Record".save_aircraft_e2_crew(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare row_data jsonb; current_revision text; principle text;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  current_revision:="Basic_Carrier_Record".get_aircraft_e2(p_iata,p_type_code,p_subtype)->>'revision';if current_revision<>p_revision then raise exception 'Revision conflict' using errcode='40001';end if;
  select "Start_Weight_Principle" into principle from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type_code and "Aircraft_Series_Subtype"=p_subtype;
  if principle='DRY_OPERATING_WEIGHT' then
    if (select count(distinct r->>'crewCode') from jsonb_array_elements(p_rows) r where coalesce((r->>'isBase')::boolean,false))<>1 then raise exception 'Select exactly one base crew code' using errcode='23514'; end if;
    if exists(select 1 from jsonb_array_elements(p_rows) r where jsonb_typeof(r->'weightAdjustment')<>'number' or jsonb_typeof(r->'indexAdjustment')<>'number') then raise exception 'Enter every crew DOW and DOI adjustment' using errcode='23514'; end if;
    if exists(select 1 from jsonb_array_elements(p_rows) a cross join jsonb_array_elements(p_rows) b where a->>'crewCode'=b->>'crewCode' and (coalesce((a->>'isBase')::boolean,false) is distinct from coalesce((b->>'isBase')::boolean,false) or (a->>'weightAdjustment')::numeric is distinct from (b->>'weightAdjustment')::numeric or (a->>'indexAdjustment')::numeric is distinct from (b->>'indexAdjustment')::numeric)) then raise exception 'Each crew code must use one consistent DOW and DOI deviation' using errcode='23514'; end if;
    if exists(select 1 from jsonb_array_elements(p_rows) r where coalesce((r->>'isBase')::boolean,false) and ((r->>'weightAdjustment')::numeric<>0 or (r->>'indexAdjustment')::numeric<>0)) then raise exception 'Base crew adjustments must be zero' using errcode='23514'; end if;
  end if;
  delete from "Basic_Carrier_Record"."Aircraft_Crew_Codes" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type_code and "Aircraft_Series_Subtype"=p_subtype;
  for row_data in select value from jsonb_array_elements(p_rows) loop
    insert into "Basic_Carrier_Record"."Aircraft_Crew_Codes"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Crew_Code_ID","Flight_Deck_Location_Short_Form_ID","Flight_Deck_Seats_Occupied","Cabin_Crew_Location_Short_Form_ID","Cabin_Crew_Seats_Occupied","Flight_Deck_Baggage_Location","Cabin_Crew_Baggage_Location","Is_DOW_Base","DOW_Weight_Adjustment","DOI_Adjustment")
    values(p_iata,p_type_code,p_subtype,row_data->>'crewCode',row_data->>'flightDeckLocationId',(row_data->>'flightDeckSeats')::integer,nullif(row_data->>'cabinCrewLocationId',''),(row_data->>'cabinCrewSeats')::integer,nullif(row_data->>'flightDeckBaggageLocation',''),nullif(row_data->>'cabinCrewBaggageLocation',''),case when principle='DRY_OPERATING_WEIGHT' then coalesce((row_data->>'isBase')::boolean,false) else false end,case when principle='DRY_OPERATING_WEIGHT' then (row_data->>'weightAdjustment')::integer else null end,case when principle='DRY_OPERATING_WEIGHT' then (row_data->>'indexAdjustment')::double precision else null end);
  end loop;return "Basic_Carrier_Record".get_aircraft_e2(p_iata,p_type_code,p_subtype);
end$$;

revoke all on function "Basic_Carrier_Record".save_aircraft_e2_crew(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_e2_crew(text,text,text,text,jsonb) to authenticated;

commit;
