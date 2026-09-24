begin;

create table if not exists "Basic_Carrier_Record"."Aircraft_Limiting_Weights" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Table_Name" varchar(20) not null,
  "Limit_Condition" varchar(200),
  "Limit_Condition_Code" varchar(20),
  "Limit_From_Date" date,
  "Limit_To_Date" date,
  "Limit_Type" varchar(30),
  constraint "Aircraft_Limiting_Weights_pkey" primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name"),
  constraint "Aircraft_Limiting_Weights_aircraft_fkey" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update cascade on delete cascade,
  constraint "Aircraft_Limiting_Weights_table_name_check" check (btrim("Table_Name") ~ '^[A-Z0-9][A-Z0-9 /_-]{0,19}$'),
  constraint "Aircraft_Limiting_Weights_date_order_check" check ("Limit_From_Date" is null or "Limit_To_Date" is null or "Limit_From_Date" <= "Limit_To_Date")
);

create table if not exists "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Table_Name" varchar(20) not null,
  "Aircraft_Registration" varchar(10) not null,
  "Zero_Fuel_Weight" integer not null,
  "Landing_Weight" integer not null,
  "Take_Off_Weight" integer not null,
  "Ramp_Taxi_Weight" integer not null,
  "Remarks" varchar(500),
  constraint "Aircraft_Limiting_Weight_Values_pkey" primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Aircraft_Registration"),
  constraint "Aircraft_Limiting_Weight_Values_table_fkey" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name") references "Basic_Carrier_Record"."Aircraft_Limiting_Weights"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name") on update cascade on delete restrict,
  constraint "Aircraft_Limiting_Weight_Values_registration_check" check (btrim("Aircraft_Registration") ~ '^[A-Z0-9][A-Z0-9-]{0,9}$'),
  constraint "Aircraft_Limiting_Weight_Values_hierarchy_check" check ("Zero_Fuel_Weight">0 and "Zero_Fuel_Weight"<="Landing_Weight" and "Landing_Weight"<="Take_Off_Weight" and "Take_Off_Weight"<="Ramp_Taxi_Weight")
);

alter table "Basic_Carrier_Record"."Aircraft_Limiting_Weights" enable row level security;
alter table "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" enable row level security;

create policy "aircraft_limiting_weights_select" on "Basic_Carrier_Record"."Aircraft_Limiting_Weights" for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "aircraft_limiting_weights_insert" on "Basic_Carrier_Record"."Aircraft_Limiting_Weights" for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_limiting_weights_update" on "Basic_Carrier_Record"."Aircraft_Limiting_Weights" for update to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_limiting_weights_delete" on "Basic_Carrier_Record"."Aircraft_Limiting_Weights" for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_limiting_values_select" on "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "aircraft_limiting_values_insert" on "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_limiting_values_update" on "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" for update to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "aircraft_limiting_values_delete" on "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_Limiting_Weights" to authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" to authenticated;

create or replace function "Basic_Carrier_Record".get_aircraft_f1(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code)); st text:=upper(btrim(p_subtype)); can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')); can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  unit text; mzfw integer; mlaw integer; mtow integer; mrw integer; defs jsonb; vals jsonb; regs jsonb; first_reg text; payload jsonb;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  select a."MZFW",a."MLAW",a."MTOW",a."MRW",coalesce(s."Weight_Unit",'Kg') into mzfw,mlaw,mtow,mrw,unit
    from "Basic_Carrier_Record"."Basic_Aircraft_Data" a left join "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" s using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st;
  if not found then raise exception 'Aircraft not found' using errcode='23503'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('tableId',null,'tableName',btrim(d."Table_Name"),'limitCondition',nullif(btrim(d."Limit_Condition"),''),'limitConditionCode',nullif(btrim(d."Limit_Condition_Code"),''),'limitFromDate',d."Limit_From_Date",'limitToDate',d."Limit_To_Date",'limitType',nullif(btrim(d."Limit_Type"),''),'persisted',true) order by btrim(d."Table_Name")),'[]'::jsonb) into defs
    from "Basic_Carrier_Record"."Aircraft_Limiting_Weights" d where d."Carrier_IATA"=p_iata and d."Aircraft_Type_IATA"=tc and d."Aircraft_Series_Subtype"=st;
  if jsonb_array_length(defs)=0 then defs:=jsonb_build_array(jsonb_build_object('tableId',null,'tableName','ALL','limitCondition',null,'limitConditionCode',null,'limitFromDate',null,'limitToDate',null,'limitType',null,'persisted',false)); end if;
  select coalesce(jsonb_agg(to_jsonb(q.registration) order by q.registration),'[]'::jsonb),min(q.registration) into regs,first_reg from (
    select distinct upper(btrim(f."Aircraft_Registration")) registration from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st
  ) q;
  select coalesce(jsonb_agg(jsonb_build_object('rowId',null,'tableName',btrim(v."Table_Name"),'registration',btrim(v."Aircraft_Registration"),'zeroFuelWeight',v."Zero_Fuel_Weight",'landingWeight',v."Landing_Weight",'takeOffWeight',v."Take_Off_Weight",'rampTaxiWeight',v."Ramp_Taxi_Weight",'remarks',nullif(btrim(v."Remarks"),''),'persisted',true) order by btrim(v."Table_Name"),btrim(v."Aircraft_Registration")),'[]'::jsonb) into vals
    from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" v where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st;
  if jsonb_array_length(vals)=0 and first_reg is not null then vals:=jsonb_build_array(jsonb_build_object('rowId',null,'tableName','ALL','registration',first_reg,'zeroFuelWeight',mzfw,'landingWeight',mlaw,'takeOffWeight',mtow,'rampTaxiWeight',mrw,'remarks',null,'persisted',false)); end if;
  payload:=jsonb_build_object('typeCode',tc,'subtype',st,'weightUnit',unit,'definitions',defs,'rows',vals,'registrationOptions',regs,'c5Source',jsonb_build_object('mzfw',mzfw,'mlaw',mlaw,'mtow',mtow,'mrw',mrw));
  return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text));
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_f1_definitions(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code)); st text:=upper(btrim(p_subtype)); item jsonb; n text; current_data jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  current_data:="Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st); if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one table required' using errcode='22023'; end if;
  if exists(select 1 from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" v where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st and not exists(select 1 from jsonb_array_elements(p_rows) r where upper(btrim(r->>'tableName'))=btrim(v."Table_Name"))) then raise exception 'A table used by a limiting weight row cannot be removed' using errcode='23503'; end if;
  delete from "Basic_Carrier_Record"."Aircraft_Limiting_Weights" d where d."Carrier_IATA"=p_iata and d."Aircraft_Type_IATA"=tc and d."Aircraft_Series_Subtype"=st and not exists(select 1 from jsonb_array_elements(p_rows) r where upper(btrim(r->>'tableName'))=btrim(d."Table_Name"));
  for item in select value from jsonb_array_elements(p_rows) loop
    n:=upper(btrim(item->>'tableName'));
    insert into "Basic_Carrier_Record"."Aircraft_Limiting_Weights"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Limit_Condition","Limit_Condition_Code","Limit_From_Date","Limit_To_Date","Limit_Type") values(p_iata,tc,st,n,nullif(btrim(item->>'limitCondition'),''),nullif(upper(btrim(item->>'limitConditionCode')),''),nullif(item->>'limitFromDate','')::date,nullif(item->>'limitToDate','')::date,nullif(upper(btrim(item->>'limitType')),'')) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name") do update set "Limit_Condition"=excluded."Limit_Condition","Limit_Condition_Code"=excluded."Limit_Condition_Code","Limit_From_Date"=excluded."Limit_From_Date","Limit_To_Date"=excluded."Limit_To_Date","Limit_Type"=excluded."Limit_Type";
  end loop;
  return "Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_f1_rows(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code)); st text:=upper(btrim(p_subtype)); item jsonb; tn text; reg text; z integer; l integer; t integer; r integer; rem text; current_data jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  current_data:="Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st); if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023'; end if;
  insert into "Basic_Carrier_Record"."Aircraft_Limiting_Weights"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name") values(p_iata,tc,st,'ALL') on conflict do nothing;
  delete from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  for item in select value from jsonb_array_elements(p_rows) loop
    tn:=upper(btrim(item->>'tableName')); reg:=upper(btrim(item->>'registration')); z:=nullif(item->>'zeroFuelWeight','')::integer; l:=nullif(item->>'landingWeight','')::integer; t:=nullif(item->>'takeOffWeight','')::integer; r:=nullif(item->>'rampTaxiWeight','')::integer; rem:=nullif(btrim(item->>'remarks'),'');
    if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Limiting_Weights" d where d."Carrier_IATA"=p_iata and d."Aircraft_Type_IATA"=tc and d."Aircraft_Series_Subtype"=st and d."Table_Name"=tn) then raise exception 'Unknown Weight Table Name' using errcode='23503'; end if;
    if not exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st and upper(btrim(f."Aircraft_Registration"))=reg) then raise exception 'Unknown registration' using errcode='23503'; end if;
    insert into "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Aircraft_Registration","Zero_Fuel_Weight","Landing_Weight","Take_Off_Weight","Ramp_Taxi_Weight","Remarks") values(p_iata,tc,st,tn,reg,z,l,t,r,rem);
  end loop;
  return "Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_f1(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_f1_definitions(text,text,text,text,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_f1_rows(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_f1(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_f1_definitions(text,text,text,text,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_f1_rows(text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
