begin;

create table if not exists "Basic_Carrier_Record"."Carrier_Aircraft_E4_Settings" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Weight_Configurations_Active" boolean not null default false,
  "Additional_Service_Adjustments_Active" boolean not null default false,
  "Updated_At" timestamptz not null default now(),
  constraint "Carrier_Aircraft_E4_Settings_pkey" primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
  constraint "Carrier_Aircraft_E4_Settings_aircraft_fkey" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update cascade on delete cascade,
  constraint "Carrier_Aircraft_E4_Settings_additional_check" check (not "Additional_Service_Adjustments_Active" or "Weight_Configurations_Active")
);

create table if not exists "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Service_Adjustments" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Weight_Configuration_Code" varchar not null,
  "Service_Weight_Adjustment_Code" varchar not null,
  "Sequence" smallint not null default 1,
  constraint "Aircraft_Weight_Config_Service_Adjustments_pkey" primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configuration_Code","Service_Weight_Adjustment_Code"),
  constraint "Aircraft_Weight_Config_Service_Adjustments_sequence_check" check ("Sequence">0),
  constraint "Aircraft_Weight_Config_Service_Adjustments_config_fkey" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configuration_Code") references "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configuration_Code") on update cascade on delete cascade,
  constraint "Aircraft_Weight_Config_Service_Adjustments_service_fkey" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Service_Weight_Adjustment_Code") references "Basic_Carrier_Record"."Aircraft_Service_Weight_Adjustment_Codes"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Service_Weight_Adjustment_Code") on update cascade on delete restrict
);

insert into "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Service_Adjustments"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configuration_Code","Service_Weight_Adjustment_Code","Sequence")
select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configuration_Code","Service_Weight_Adjustment_Code_2",1 from "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" where "Service_Weight_Adjustment_Code_2" is not null on conflict do nothing;
alter table "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" drop constraint if exists "Aircraft_Weight_Config_Service_Adjustment_2_FK";
alter table "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" drop column if exists "Service_Weight_Adjustment_Code_2";

alter table "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" drop constraint if exists "Aircraft_Weight_Config_Potable_Water_FK";
alter table "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" add constraint "Aircraft_Weight_Config_Potable_Water_FK" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Potable_Water_Code") references "Basic_Carrier_Record"."Aircraft_Potable_Water_Code_Definitions"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Potable_Water_Code") on update cascade on delete restrict;

insert into "Basic_Carrier_Record"."Carrier_Aircraft_E4_Settings"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configurations_Active","Additional_Service_Adjustments_Active")
select a."Carrier_IATA",a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype",true,exists(select 1 from "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Service_Adjustments" x where x."Carrier_IATA"=a."Carrier_IATA" and x."Aircraft_Type_IATA"=a."Aircraft_Type_IATA" and x."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype")
from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where exists(select 1 from "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" c where c."Carrier_IATA"=a."Carrier_IATA" and c."Aircraft_Type_IATA"=a."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype") on conflict do nothing;

alter table "Basic_Carrier_Record"."Carrier_Aircraft_E4_Settings" enable row level security;
alter table "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Service_Adjustments" enable row level security;

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

create or replace function "Basic_Carrier_Record".save_aircraft_e4_applicability(p_iata text,p_type_code text,p_subtype text,p_revision text,p_active boolean,p_additional_active boolean)
returns jsonb language plpgsql security definer set search_path='' as $$ declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype)); begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_e4(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if p_additional_active and not p_active then raise exception 'Additional section requires main section' using errcode='23514'; end if;
  insert into "Basic_Carrier_Record"."Carrier_Aircraft_E4_Settings"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configurations_Active","Additional_Service_Adjustments_Active","Updated_At") values(p_iata,tc,st,p_active,p_additional_active,now()) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "Weight_Configurations_Active"=excluded."Weight_Configurations_Active","Additional_Service_Adjustments_Active"=excluded."Additional_Service_Adjustments_Active","Updated_At"=now();
  return "Basic_Carrier_Record".get_aircraft_e4(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_e4_configurations(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$ declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb; begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_e4(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023'; end if;
  delete from "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  for item in select value from jsonb_array_elements(p_rows) loop insert into "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configuration_Code","Crew_Code","Pantry_Code","Potable_Water_Code","Service_Weight_Adjustment_Code_1") values(p_iata,tc,st,upper(btrim(item->>'code')),upper(btrim(item->>'crewCode')),upper(btrim(item->>'pantryCode')),nullif(upper(btrim(item->>'waterCode')),''),nullif(upper(btrim(item->>'serviceCode')),'')); end loop;
  return "Basic_Carrier_Record".get_aircraft_e4(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_e4_additional(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$ declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;n integer:=0; begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_e4(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023'; end if;
  delete from "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Service_Adjustments" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  for item in select value from jsonb_array_elements(p_rows) loop n:=n+1;insert into "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Service_Adjustments"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configuration_Code","Service_Weight_Adjustment_Code","Sequence") values(p_iata,tc,st,upper(btrim(item->>'configurationCode')),upper(btrim(item->>'serviceCode')),n); end loop;
  return "Basic_Carrier_Record".get_aircraft_e4(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_e4(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_e4_applicability(text,text,text,text,boolean,boolean) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_e4_configurations(text,text,text,text,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_e4_additional(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_e4(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_e4_applicability(text,text,text,text,boolean,boolean) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_e4_configurations(text,text,text,text,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_e4_additional(text,text,text,text,jsonb) to authenticated;

commit;
