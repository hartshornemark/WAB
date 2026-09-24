begin;

alter table "Basic_Carrier_Record"."Basic_Aircraft_Data" add column if not exists "Weight_Recording_Approach" varchar(32);
alter table "Basic_Carrier_Record"."Basic_Aircraft_Data" drop constraint if exists "Basic_Aircraft_Data_Weight_Recording_Approach_check";
alter table "Basic_Carrier_Record"."Basic_Aircraft_Data" add constraint "Basic_Aircraft_Data_Weight_Recording_Approach_check" check("Weight_Recording_Approach" is null or "Weight_Recording_Approach" in ('FLEET_WEIGHTS','INDIVIDUAL_AIRCRAFT_WEIGHTS'));

alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add column if not exists "Fleet_Weight_Adjustment" integer;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add column if not exists "Fleet_Index_Adjustment" double precision;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add column if not exists "MAC_Percent" double precision;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add column if not exists "Balance_Arm" double precision;
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add column if not exists "Weight_Configuration_Code" varchar(3);
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add column if not exists "Remarks" varchar(500);
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_reference_row_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_MAC_Percent_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_MAC_Percent_check" check("MAC_Percent" is null or abs("MAC_Percent")<=1000000000);
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_Balance_Arm_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_Balance_Arm_check" check("Balance_Arm" is null or abs("Balance_Arm")<=1000000000);
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_Fleet_Index_Adjustment_check";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_Fleet_Index_Adjustment_check" check("Fleet_Index_Adjustment" is null or abs("Fleet_Index_Adjustment")<=1000000000);
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" drop constraint if exists "Carrier_Aircraft_Fleet_Weight_Configuration_FK";
alter table "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" add constraint "Carrier_Aircraft_Fleet_Weight_Configuration_FK" foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configuration_Code") references "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Weight_Configuration_Code") on update cascade on delete restrict;

update "Basic_Carrier_Record"."Basic_Aircraft_Data" a set "Weight_Recording_Approach"='FLEET_WEIGHTS' where "Weight_Recording_Approach" is null and "Standard_Fleet_Weight" is not null and "Standard_Fleet_Index" is not null and exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f where f."Carrier_IATA"=a."Carrier_IATA" and f."Aircraft_Type_IATA"=a."Aircraft_Type_IATA" and f."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype" and f."E1_2_Registration_Reference");
update "Basic_Carrier_Record"."Basic_Aircraft_Data" a set "Weight_Recording_Approach"='INDIVIDUAL_AIRCRAFT_WEIGHTS' where "Weight_Recording_Approach" is null and exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f where f."Carrier_IATA"=a."Carrier_IATA" and f."Aircraft_Type_IATA"=a."Aircraft_Type_IATA" and f."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype" and f."E1_2_Registration_Reference");
update "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f set "Fleet_Weight_Adjustment"=case when a."Start_Weight_Principle"='BASIC_WEIGHT' then f."Basic_Weight"-a."Standard_Fleet_Weight" else f."Dry_Operating_Weight"-a."Standard_Fleet_Weight" end,"Fleet_Index_Adjustment"=case when a."Start_Weight_Principle"='BASIC_WEIGHT' then f."Basic_Index"-a."Standard_Fleet_Index" else f."Dry_Operating_Index"-a."Standard_Fleet_Index" end from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where f."Carrier_IATA"=a."Carrier_IATA" and f."Aircraft_Type_IATA"=a."Aircraft_Type_IATA" and f."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype" and f."E1_2_Registration_Reference" and a."Weight_Recording_Approach"='FLEET_WEIGHTS' and f."Fleet_Weight_Adjustment" is null and f."Fleet_Index_Adjustment" is null and a."Standard_Fleet_Weight" is not null and a."Standard_Fleet_Index" is not null and (case when a."Start_Weight_Principle"='BASIC_WEIGHT' then f."Basic_Weight" else f."Dry_Operating_Weight" end) is not null and (case when a."Start_Weight_Principle"='BASIC_WEIGHT' then f."Basic_Index" else f."Dry_Operating_Index" end) is not null;

create or replace function "Basic_Carrier_Record".get_aircraft_e5(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));p text;a text;fw integer;fi double precision;rows jsonb;configs jsonb;pantry jsonb;crew jsonb;can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');payload jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select "Start_Weight_Principle","Weight_Recording_Approach","Standard_Fleet_Weight","Standard_Fleet_Index" into p,a,fw,fi from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if not found or p is null then raise exception 'Complete E1.1 first' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('fleetRowId',f."Fleet_Row_ID",'registration',btrim(f."Aircraft_Registration"),'weight',case when a='FLEET_WEIGHTS' then f."Fleet_Weight_Adjustment" when p='BASIC_WEIGHT' then f."Basic_Weight" else f."Dry_Operating_Weight" end,'index',case when a='FLEET_WEIGHTS' then f."Fleet_Index_Adjustment" when p='BASIC_WEIGHT' then f."Basic_Index" else f."Dry_Operating_Index" end,'actualWeight',case when p='BASIC_WEIGHT' then f."Basic_Weight" else f."Dry_Operating_Weight" end,'actualIndex',case when p='BASIC_WEIGHT' then f."Basic_Index" else f."Dry_Operating_Index" end,'macPercent',f."MAC_Percent",'balanceArm',f."Balance_Arm",'weightConfigurationCode',nullif(btrim(f."Weight_Configuration_Code"),''),'pantryCode',nullif(btrim(f."Pantry_Code_ID"),''),'crewCode',nullif(btrim(f."Crew_Code_ID"),''),'remarks',nullif(btrim(f."Remarks"),'')) order by btrim(f."Aircraft_Registration")),'[]'::jsonb) into rows from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st and f."E1_2_Registration_Reference";
 select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Weight_Configuration_Code"),'label',btrim(x."Weight_Configuration_Code")) order by btrim(x."Weight_Configuration_Code")),'[]') into configs from "Basic_Carrier_Record"."Aircraft_Weight_Configuration_Codes" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Pantry_Code_ID"),'label',coalesce(nullif(btrim(x."Pantry_Galley_Locations"),''),btrim(x."Pantry_Code_ID"))) order by btrim(x."Pantry_Code_ID")),'[]') into pantry from "Basic_Carrier_Record"."Aircraft_Pantry_Codes" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('code',btrim(x."Crew_Code_ID"),'label',coalesce(nullif(btrim(x."Crew_Definition_Description"),''),btrim(x."Crew_Code_ID"))) order by btrim(x."Crew_Code_ID")),'[]') into crew from "Basic_Carrier_Record"."Aircraft_Crew_Code_Definitions" x where x."Carrier_IATA"=p_iata and x."Aircraft_Type_IATA"=tc and x."Aircraft_Series_Subtype"=st;
 payload:=jsonb_build_object('principle',p,'approach',a,'fleetWeight',fw,'fleetIndex',fi,'rows',rows,'configurationOptions',configs,'pantryOptions',pantry,'crewOptions',crew);
 return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text),'typeCode',tc,'subtype',st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_e5_approach(p_iata text,p_type_code text,p_subtype text,p_revision text,p_approach text)
returns jsonb language plpgsql security invoker set search_path='' as $$ declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e5(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 if p_approach not in ('FLEET_WEIGHTS','INDIVIDUAL_AIRCRAFT_WEIGHTS') then raise exception 'Invalid approach' using errcode='23514';end if;
 update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Weight_Recording_Approach"=p_approach where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 return "Basic_Carrier_Record".get_aircraft_e5(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_e5_rows(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;p text;a text;fw integer;fi double precision;item jsonb;reg text;w integer;i double precision;aw integer;ai double precision;mac double precision;arm double precision;wc text;pc text;cc text;rem text;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e5(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023';end if;
 p:=current_data->>'principle';a:=current_data->>'approach';fw:=nullif(current_data->>'fleetWeight','')::integer;fi:=nullif(current_data->>'fleetIndex','')::double precision;if a is null then raise exception 'Select approach' using errcode='23514';end if;if a='FLEET_WEIGHTS' and (fw is null or fi is null) then raise exception 'Complete fleet values' using errcode='23514';end if;
 delete from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference";
 for item in select value from jsonb_array_elements(p_rows) loop
  reg:=upper(btrim(item->>'registration'));w:=nullif(item->>'weight','')::integer;i:=nullif(item->>'index','')::double precision;mac:=nullif(item->>'macPercent','')::double precision;arm:=nullif(item->>'balanceArm','')::double precision;wc:=nullif(upper(btrim(item->>'weightConfigurationCode')),'');pc:=case when a='FLEET_WEIGHTS' then nullif(upper(btrim(item->>'pantryCode')),'') else null end;cc:=case when a='FLEET_WEIGHTS' then nullif(upper(btrim(item->>'crewCode')),'') else null end;rem:=nullif(btrim(item->>'remarks'),'');
  if reg !~ '^[A-Z0-9][A-Z0-9-]{0,9}$' or w is null or i is null or (a='INDIVIDUAL_AIRCRAFT_WEIGHTS' and w<=0) or abs(i)>1000000000 or (mac is not null and abs(mac)>1000000000) or (arm is not null and abs(arm)>1000000000) or length(coalesce(rem,''))>500 then raise exception 'Invalid E5 row' using errcode='23514';end if;
  aw:=case when a='FLEET_WEIGHTS' then fw+w else w end;ai:=case when a='FLEET_WEIGHTS' then fi+i else i end;if aw<=0 then raise exception 'Invalid actual weight' using errcode='23514';end if;
  insert into "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Aircraft_Registration","Carrier_IATA","Aircraft_Type_IATA","Crew_Code_ID","Pantry_Code_ID","Dry_Operating_Weight","Dry_Operating_Index","Aircraft_Series_Subtype","Basic_Weight","Basic_Index","E1_2_Registration_Reference","Fleet_Weight_Adjustment","Fleet_Index_Adjustment","MAC_Percent","Balance_Arm","Weight_Configuration_Code","Remarks") values(reg,p_iata,tc,cc,pc,case when p='DRY_OPERATING_WEIGHT' then aw else null end,case when p='DRY_OPERATING_WEIGHT' then ai else null end,st,case when p='BASIC_WEIGHT' then aw else null end,case when p='BASIC_WEIGHT' then ai else null end,true,case when a='FLEET_WEIGHTS' then w else null end,case when a='FLEET_WEIGHTS' then i else null end,mac,arm,wc,rem);
 end loop;
 return "Basic_Carrier_Record".get_aircraft_e5(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_e5(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_e5_approach(text,text,text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_e5_rows(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_e5(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_e5_approach(text,text,text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_e5_rows(text,text,text,text,jsonb) to authenticated;

commit;
