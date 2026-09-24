begin;

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

create or replace function "Basic_Carrier_Record".get_aircraft_e4(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean;can_edit boolean;settings jsonb;configs jsonb;additional jsonb;crew jsonb;pantry jsonb;water jsonb;service jsonb;
begin
  can_view:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW');
  can_edit:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503'; end if;
  select to_jsonb(s) into settings from "Basic_Carrier_Record"."Carrier_Aircraft_E4_Settings" s where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(c."Weight_Configuration_Code"),'crewCode',btrim(c."Crew_Code"),'pantryCode',btrim(c."Pantry_Code"),'waterCode',nullif(btrim(c."Potable_Water_Code"),''),'serviceCode',nullif(btrim(c."Service_Weight_Adjustment_Code_1"),'')) order by btrim(c."Weight_Configuration_Code")),'[]') into configs from "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(jsonb_build_object('configurationCode',btrim(x."Weight_Configuration_Code"),'serviceCode',btrim(x."Service_Weight_Adjustment_Code")) order by btrim(x."Weight_Configuration_Code"),x."Sequence",btrim(x."Service_Weight_Adjustment_Code")),'[]') into additional from "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Service_Adjustments" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Crew_Code_ID"),'label',coalesce(nullif(btrim(x."Crew_Definition_Description"),''),btrim(x."Crew_Code_ID"))) order by btrim(x."Crew_Code_ID")),'[]') into crew
  from "Basic_Carrier_Record"."Aircraft_Crew_Code_Definitions" x
  where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st
    and exists (
      select 1 from "Basic_Carrier_Record"."Aircraft_Crew_Codes" c
      where c."Carrier_IATA"=x."Carrier_IATA" and c."Aircraft_Type_IATA"=x."Aircraft_Type_IATA"
        and c."Aircraft_Series_Subtype"=x."Aircraft_Series_Subtype" and c."Crew_Code_ID"=x."Crew_Code_ID"
    );
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Pantry_Code_ID"),'label',coalesce(nullif(btrim(x."Pantry_Galley_Locations"),''),btrim(x."Pantry_Code_ID"))) order by btrim(x."Pantry_Code_ID")),'[]') into pantry from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Potable_Water_Code"),'label',btrim(x."Potable_Water_Code")) order by btrim(x."Potable_Water_Code")),'[]') into water from "Basic_Carrier_Record"."Aircraft_Potable_Water_Code_Definitions" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Service_Weight_Adjustment_Code"),'label',btrim(x."Service_Weight_Adjustment_Description")) order by btrim(x."Service_Weight_Adjustment_Code")),'[]') into service from "Basic_Carrier_Record"."Aircraft_Service_Weight_Adjustment_Codes" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
  return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(coalesce(settings::text,'null')||configs::text||additional::text),'typeCode',tc,'subtype',st,'applicabilityReviewed',settings is not null,'active',coalesce((settings->>'Weight_Configurations_Active')::boolean,false),'additionalActive',coalesce((settings->>'Additional_Service_Adjustments_Active')::boolean,false),'configurations',configs,'additionalRows',additional,'crewOptions',crew,'pantryOptions',pantry,'waterOptions',water,'serviceOptions',service);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_e4(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_e4(text,text,text) to authenticated;

commit;
