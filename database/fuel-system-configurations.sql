begin;

create table "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations"(
  "Carrier_IATA" varchar(3) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(20) not null,
  "Configuration_Code" varchar(12) not null check (btrim("Configuration_Code") ~ '^[A-Z0-9][A-Z0-9-]{0,11}$'),
  "Description" varchar(120) not null default '',
  "ACT_Count" smallint not null check ("ACT_Count" between 0 and 9),
  "MRW" integer check ("MRW" is null or "MRW">0),
  "MTOW" integer check ("MTOW" is null or "MTOW">0),
  "MLAW" integer check ("MLAW" is null or "MLAW">0),
  "MZFW" integer check ("MZFW" is null or "MZFW">0),
  "Updated_At" timestamptz not null default now(),
  primary key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code"),
  constraint "aircraft_fuel_configuration_aircraft_fk" foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update cascade on delete cascade,
  constraint "aircraft_fuel_configuration_weights_complete" check (("MRW" is null and "MTOW" is null and "MLAW" is null and "MZFW" is null) or ("MRW" is not null and "MTOW" is not null and "MLAW" is not null and "MZFW" is not null and "MZFW"<="MLAW" and "MLAW"<="MTOW" and "MTOW"<="MRW"))
);

create table "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations"(
  "Carrier_IATA" varchar(3) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(20) not null,
  "Aircraft_Registration" varchar(10) not null check (btrim("Aircraft_Registration") ~ '^[A-Z0-9][A-Z0-9-]{0,9}$'),
  "Configuration_Code" varchar(12) not null,
  "Updated_At" timestamptz not null default now(),
  primary key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Registration"),
  constraint "aircraft_registration_fuel_configuration_fk" foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code") references "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code") on update cascade on delete cascade
);

alter table "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" enable row level security;
alter table "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" enable row level security;
grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" to authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" to authenticated;

create policy "perm_aircraft_select" on "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_update" on "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" for update to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_select" on "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_update" on "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" for update to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

create or replace function "Basic_Carrier_Record".get_aircraft_e12(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));p text;sfw integer;sfi double precision;rows jsonb;variants jsonb;fuel_configs jsonb;can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');payload jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 select "Start_Weight_Principle","Standard_Fleet_Weight","Standard_Fleet_Index" into p,sfw,sfi from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if not found or p is null then raise exception 'Complete E1.1 first' using errcode='23503';end if;
 select coalesce(jsonb_agg("Carrier_Variant_Code" order by "Carrier_Variant_Code"),'[]'::jsonb) into variants from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('code',"Configuration_Code",'description',"Description",'actCount',"ACT_Count",'maximumWeights',jsonb_build_object('mrw',"MRW",'tow',"MTOW",'law',"MLAW",'zfw',"MZFW")) order by "ACT_Count","Configuration_Code"),'[]'::jsonb) into fuel_configs from "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 select coalesce(jsonb_agg(jsonb_build_object('fleetRowId',f."Fleet_Row_ID",'registration',btrim(f."Aircraft_Registration"),'variantCode',f."Carrier_Variant_Code",'fuelConfigurationCode',m."Configuration_Code",'weight',case when p='BASIC_WEIGHT' then f."Basic_Weight" else f."Dry_Operating_Weight" end,'index',case when p='BASIC_WEIGHT' then f."Basic_Index" else f."Dry_Operating_Index" end) order by btrim(f."Aircraft_Registration")),'[]'::jsonb) into rows from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f left join "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" m on m."Carrier_IATA"=f."Carrier_IATA" and m."Aircraft_Type_IATA"=f."Aircraft_Type_IATA" and m."Aircraft_Series_Subtype"=f."Aircraft_Series_Subtype" and m."Aircraft_Registration"=btrim(f."Aircraft_Registration") where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st and f."E1_2_Registration_Reference";
 payload:=jsonb_build_object('principle',p,'standardFleetWeight',sfw,'standardFleetIndex',sfi,'variantOptions',variants,'fuelConfigurations',fuel_configs,'registrations',rows);
 return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text),'typeCode',tc,'subtype',st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_fuel_configurations(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;item jsonb;code text;description text;act_count integer;mrw integer;mtow integer;mlaw integer;mzfw integer;codes text[]:='{}';
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;if jsonb_typeof(p_rows)<>'array' then raise exception 'Rows required' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_rows) loop
  code:=upper(btrim(item->>'code'));description:=btrim(coalesce(item->>'description',''));act_count:=(item->>'actCount')::integer;mrw:=nullif(item#>>'{maximumWeights,mrw}','')::integer;mtow:=nullif(item#>>'{maximumWeights,tow}','')::integer;mlaw:=nullif(item#>>'{maximumWeights,law}','')::integer;mzfw:=nullif(item#>>'{maximumWeights,zfw}','')::integer;
  if code !~ '^[A-Z0-9][A-Z0-9-]{0,11}$' or act_count not between 0 and 9 or not ((mrw is null and mtow is null and mlaw is null and mzfw is null) or (mzfw<=mlaw and mlaw<=mtow and mtow<=mrw)) then raise exception 'Invalid fuel configuration' using errcode='23514';end if;codes:=array_append(codes,code);
  insert into "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code","Description","ACT_Count","MRW","MTOW","MLAW","MZFW","Updated_At") values(p_iata,tc,st,code,description,act_count,mrw,mtow,mlaw,mzfw,now()) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code") do update set "Description"=excluded."Description","ACT_Count"=excluded."ACT_Count","MRW"=excluded."MRW","MTOW"=excluded."MTOW","MLAW"=excluded."MLAW","MZFW"=excluded."MZFW","Updated_At"=now();
 end loop;
 delete from "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and not ("Configuration_Code"=any(codes));
 return "Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_e12_registrations(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;p text;a text;fw integer;fi double precision;item jsonb;reg text;variant text;fuel_config text;w integer;i double precision;regs text[]:='{}';has_fuel_configs boolean;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;if jsonb_typeof(p_rows)<>'array' then raise exception 'Rows required' using errcode='22023';end if;p:=current_data->>'principle';has_fuel_configs:=jsonb_array_length(current_data->'fuelConfigurations')>0;
 select "Weight_Recording_Approach","Standard_Fleet_Weight","Standard_Fleet_Index" into a,fw,fi from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 for item in select value from jsonb_array_elements(p_rows) loop
  reg:=upper(btrim(item->>'registration'));variant:=upper(btrim(item->>'variantCode'));fuel_config:=nullif(upper(btrim(item->>'fuelConfigurationCode')),'');w:=nullif(item->>'weight','')::integer;i:=nullif(item->>'index','')::double precision;
  if reg !~ '^[A-Z0-9][A-Z0-9-]{0,9}$' or not exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st and v."Carrier_Variant_Code"=variant) or (has_fuel_configs and (fuel_config is null or not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and c."Configuration_Code"=fuel_config))) or (w is not null and w<=0) or (i is not null and abs(i)>1000000000) then raise exception 'Invalid registration row' using errcode='23514';end if;regs:=array_append(regs,reg);
  update "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" set "Carrier_Variant_Code"=variant,"Dry_Operating_Weight"=case when p='DRY_OPERATING_WEIGHT' then w else null end,"Dry_Operating_Index"=case when p='DRY_OPERATING_WEIGHT' then i else null end,"Basic_Weight"=case when p='BASIC_WEIGHT' then w else null end,"Basic_Index"=case when p='BASIC_WEIGHT' then i else null end,"Fleet_Weight_Adjustment"=case when a='FLEET_WEIGHTS' and w is not null and fw is not null then w-fw else "Fleet_Weight_Adjustment" end,"Fleet_Index_Adjustment"=case when a='FLEET_WEIGHTS' and i is not null and fi is not null then i-fi else "Fleet_Index_Adjustment" end where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference" and btrim("Aircraft_Registration")=reg;
  if not found then insert into "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Aircraft_Registration","Carrier_IATA","Aircraft_Type_IATA","Crew_Code_ID","Pantry_Code_ID","Dry_Operating_Weight","Dry_Operating_Index","Aircraft_Series_Subtype","Carrier_Variant_Code","Basic_Weight","Basic_Index","E1_2_Registration_Reference","Fleet_Weight_Adjustment","Fleet_Index_Adjustment") values(reg,p_iata,tc,null,null,case when p='DRY_OPERATING_WEIGHT' then w else null end,case when p='DRY_OPERATING_WEIGHT' then i else null end,st,variant,case when p='BASIC_WEIGHT' then w else null end,case when p='BASIC_WEIGHT' then i else null end,true,case when a='FLEET_WEIGHTS' and w is not null and fw is not null then w-fw else null end,case when a='FLEET_WEIGHTS' and i is not null and fi is not null then i-fi else null end);end if;
  if fuel_config is null then delete from "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Aircraft_Registration"=reg;else insert into "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Registration","Configuration_Code","Updated_At") values(p_iata,tc,st,reg,fuel_config,now()) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Aircraft_Registration") do update set "Configuration_Code"=excluded."Configuration_Code","Updated_At"=now();end if;
 end loop;
 delete from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference" and not (btrim("Aircraft_Registration")=any(regs));
 delete from "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and not ("Aircraft_Registration"=any(regs));
 return "Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_e12(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_fuel_configurations(text,text,text,text,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_e12_registrations(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_e12(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_fuel_configurations(text,text,text,text,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_e12_registrations(text,text,text,text,jsonb) to authenticated;


alter table "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" add column "Fuel_Configuration_Code" varchar(12);
alter table "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" add constraint "aircraft_balance_condition_fuel_configuration_fk" foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Fuel_Configuration_Code") references "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code") on update cascade on delete cascade;
create index "aircraft_balance_condition_fuel_configuration_idx" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Fuel_Configuration_Code");

create or replace function "Basic_Carrier_Record".get_aircraft_c5(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));payload jsonb;aircraft "Basic_Carrier_Record"."Basic_Aircraft_Data"%rowtype;condition_data jsonb;
begin
  payload:="Basic_Carrier_Record".get_aircraft_c5_legacy(p_iata,tc,st);
  select * into aircraft from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  select jsonb_build_object(
    'tow',coalesce(jsonb_agg(item order by display_order) filter(where phase='TOW'),'[]'::jsonb),
    'law',coalesce(jsonb_agg(item order by display_order) filter(where phase='LAW'),'[]'::jsonb),
    'zfw',coalesce(jsonb_agg(item order by display_order) filter(where phase='ZFW'),'[]'::jsonb)
  ) into condition_data from (
    select c."Phase" phase,c."Display_Order" display_order,jsonb_build_object(
      'id',c."Envelope_ID",'code',c."Envelope_Code",'configurationCode',c."Fuel_Configuration_Code",'conditionBasis',c."Condition_Basis",'conditionDescription',c."Condition_Description",
      'lowerBound',c."Lower_Bound",'lowerInclusive',c."Lower_Inclusive",'upperBound',c."Upper_Bound",'upperInclusive',c."Upper_Inclusive",
      'boundary',jsonb_build_object(
        'fwd',coalesce((select jsonb_agg(jsonb_build_object('weight',p."Aircraft_Weight",'indexValue',p."Envelope_Limit_Index_Value",'macValue',p."Envelope_Limit_MAC_Value") order by p."Aircraft_Weight") from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" p where p."Envelope_ID"=c."Envelope_ID" and p."Boundary"='FWD'),'[]'::jsonb),
        'aft',coalesce((select jsonb_agg(jsonb_build_object('weight',p."Aircraft_Weight",'indexValue',p."Envelope_Limit_Index_Value",'macValue',p."Envelope_Limit_MAC_Value") order by p."Aircraft_Weight") from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" p where p."Envelope_ID"=c."Envelope_ID" and p."Boundary"='AFT'),'[]'::jsonb)
      )) item
    from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" c
    where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st
  ) conditions;
  payload:=jsonb_set(payload,'{values}',(payload->'values')||jsonb_build_object(
    'envelopeModes',jsonb_build_object('tow',aircraft."TOW_Envelope_Mode",'law',aircraft."LAW_Envelope_Mode",'zfw',aircraft."ZFW_Envelope_Mode"),
    'conditionalEnvelopes',coalesce(condition_data,jsonb_build_object('tow','[]'::jsonb,'law','[]'::jsonb,'zfw','[]'::jsonb))
  ));
  payload:=payload-'revision';
  return payload||jsonb_build_object('revision',md5(payload::text));
end $$;
create or replace function "Basic_Carrier_Record".save_aircraft_c5_envelope(p_iata text,p_type_code text,p_subtype text,p_revision text,p_phase text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));phase text:=upper(btrim(p_phase));mode text;maximum integer;current_data jsonb;variant jsonb;variant_id uuid;side text;points jsonb;position integer:=0;configuration_code text;applicable_maximum integer;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
  if phase not in ('TOW','LAW','ZFW') then raise exception 'Invalid envelope phase' using errcode='22023';end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
  current_data:="Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft C5.1 changed' using errcode='40001';end if;
  mode:=p_values#>>array['envelopeModes',lower(phase)];if mode not in ('STANDARD','CONDITIONAL') then raise exception 'Invalid envelope mode' using errcode='22023';end if;
  if mode='STANDARD' then
    perform "Basic_Carrier_Record".save_aircraft_c5(p_iata,tc,st,p_revision,lower(phase),p_values);
  end if;
  execute format('update "Basic_Carrier_Record"."Basic_Aircraft_Data" set %I=$1 where "Carrier_IATA"=$2 and "Aircraft_Type_IATA"=$3 and "Aircraft_Series_Subtype"=$4',phase||'_Envelope_Mode') using mode,p_iata,tc,st;
  if mode='CONDITIONAL' then
    maximum:=case phase when 'TOW' then (p_values#>>'{maximumWeights,tow}')::integer when 'LAW' then (p_values#>>'{maximumWeights,law}')::integer else (p_values#>>'{maximumWeights,zfw}')::integer end;
    if maximum is null or maximum<=0 or jsonb_typeof(p_values#>array['conditionalEnvelopes',lower(phase)])<>'array' then raise exception 'Invalid conditional envelope data' using errcode='22023';end if;
    delete from "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Phase"=phase;
    for variant in select value from jsonb_array_elements(p_values#>array['conditionalEnvelopes',lower(phase)]) loop
      if coalesce(btrim(variant->>'code'),'')='' or variant->>'conditionBasis' not in ('TAKE_OFF_FUEL','LANDING_FUEL','OTHER') then raise exception 'Check every conditional envelope' using errcode='23514';end if;
      configuration_code:=nullif(upper(btrim(variant->>'configurationCode')),'');applicable_maximum:=maximum;if configuration_code is not null then select case phase when 'TOW' then "MTOW" when 'LAW' then "MLAW" else "MZFW" end into applicable_maximum from "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Configuration_Code"=configuration_code;if applicable_maximum is null then raise exception 'Select a valid fitted fuel configuration with structural weights' using errcode='23514';end if;end if;
      variant_id:=coalesce(nullif(variant->>'id','')::uuid,gen_random_uuid());
      insert into "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions" ("Envelope_ID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Phase","Fuel_Configuration_Code","Envelope_Code","Condition_Basis","Condition_Description","Lower_Bound","Lower_Inclusive","Upper_Bound","Upper_Inclusive","Display_Order") values (variant_id,p_iata,tc,st,phase,configuration_code,upper(btrim(variant->>'code')),variant->>'conditionBasis',coalesce(variant->>'conditionDescription',''),nullif(variant->>'lowerBound','')::integer,coalesce((variant->>'lowerInclusive')::boolean,false),nullif(variant->>'upperBound','')::integer,coalesce((variant->>'upperInclusive')::boolean,false),position);
      foreach side in array array['fwd','aft'] loop
        points:=variant#>array['boundary',side];if not private.c5_points_saveable(points,applicable_maximum) then raise exception 'Check every conditional envelope point' using errcode='23514';end if;
        insert into "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Condition_Points" ("Envelope_ID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Boundary","Aircraft_Weight","Envelope_Limit_Index_Value","Envelope_Limit_MAC_Value") select variant_id,p_iata,tc,st,upper(side),x.weight,x."indexValue",x."macValue" from jsonb_to_recordset(points) as x(weight integer,"indexValue" double precision,"macValue" double precision);
      end loop;
      position:=position+1;
    end loop;
  end if;
  return "Basic_Carrier_Record".get_aircraft_c5(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_c5(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_c5(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_c5_envelope(text,text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_c5_envelope(text,text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
