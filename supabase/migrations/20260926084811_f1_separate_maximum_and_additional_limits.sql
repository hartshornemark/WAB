-- Separate ALL maximum weights from additional minimum/maximum tables.
ALTER TABLE "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
 DROP CONSTRAINT "Aircraft_Limiting_Weight_Values_hierarchy_check",
 DROP CONSTRAINT "Aircraft_Limiting_Weight_Values_scope_check",
 ALTER COLUMN "Zero_Fuel_Weight" DROP NOT NULL,
 ALTER COLUMN "Landing_Weight" DROP NOT NULL,
 ALTER COLUMN "Take_Off_Weight" DROP NOT NULL,
 ALTER COLUMN "Ramp_Taxi_Weight" DROP NOT NULL,
 ADD CONSTRAINT f1_weight_values_check CHECK (
 ("Zero_Fuel_Weight" IS NULL OR "Zero_Fuel_Weight">0) AND
 ("Landing_Weight" IS NULL OR "Landing_Weight">0) AND
 ("Take_Off_Weight" IS NULL OR "Take_Off_Weight">0) AND
 ("Ramp_Taxi_Weight" IS NULL OR "Ramp_Taxi_Weight">0) AND
 num_nonnulls("Zero_Fuel_Weight","Landing_Weight","Take_Off_Weight","Ramp_Taxi_Weight")>0 AND
 ("Table_Name"<>'ALL' OR (num_nonnulls("Zero_Fuel_Weight","Landing_Weight","Take_Off_Weight","Ramp_Taxi_Weight")=4 AND "Zero_Fuel_Weight"<="Landing_Weight" AND "Landing_Weight"<="Take_Off_Weight" AND "Take_Off_Weight"<="Ramp_Taxi_Weight"))),
 ADD CONSTRAINT f1_registration_scope_check CHECK ("Aircraft_Registration" IS NULL OR btrim("Aircraft_Registration") ~ '^[A-Z0-9][A-Z0-9-]{0,9}$');
CREATE OR REPLACE FUNCTION private.sync_c5_from_f1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare iata text:=coalesce(new."Carrier_IATA",old."Carrier_IATA"); tc text:=coalesce(new."Aircraft_Type_IATA",old."Aircraft_Type_IATA"); st text:=coalesce(new."Aircraft_Series_Subtype",old."Aircraft_Series_Subtype"); z integer; l integer; t integer; r integer;
begin
  select max(v."Zero_Fuel_Weight"),max(v."Landing_Weight"),max(v."Take_Off_Weight"),max(v."Ramp_Taxi_Weight") into z,l,t,r
    from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" v
    where v."Table_Name"='ALL' and v."Carrier_IATA"=iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st;
  if z is not null then
    update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "MZFW"=z,"MLAW"=l,"MTOW"=t,"MRW"=r
      where "Carrier_IATA"=iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION private.validate_c5_f1_maximums()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare z integer; l integer; t integer; r integer;
begin
  select max(v."Zero_Fuel_Weight"),max(v."Landing_Weight"),max(v."Take_Off_Weight"),max(v."Ramp_Taxi_Weight") into z,l,t,r
    from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" v
    where v."Table_Name"='ALL' and v."Carrier_IATA"=new."Carrier_IATA" and v."Aircraft_Type_IATA"=new."Aircraft_Type_IATA" and v."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype";
  if z is not null and (new."MZFW" is distinct from z or new."MLAW" is distinct from l or new."MTOW" is distinct from t or new."MRW" is distinct from r) then
    raise exception 'C5.1 maximum weights must equal the highest corresponding F1 registration limits' using errcode='23514';
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".save_aircraft_f1_definitions(p_iata text, p_type_code text, p_subtype text, p_revision text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare tc text:=upper(btrim(p_type_code)); st text:=upper(btrim(p_subtype)); item jsonb; n text; current_data jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  current_data:="Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st); if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one table required' using errcode='22023'; end if;
  if not exists(select 1 from jsonb_array_elements(p_rows) r where upper(btrim(r->>'tableName'))='ALL') then raise exception 'The default ALL Weight Table is required' using errcode='23514'; end if;
  if exists(select 1 from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" v where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st and not exists(select 1 from jsonb_array_elements(p_rows) r where upper(btrim(r->>'tableName'))=btrim(v."Table_Name"))) then raise exception 'A table used by a limiting weight row cannot be removed' using errcode='23503'; end if;
  delete from "Basic_Carrier_Record"."Aircraft_Limiting_Weights" d where d."Carrier_IATA"=p_iata and d."Aircraft_Type_IATA"=tc and d."Aircraft_Series_Subtype"=st and not exists(select 1 from jsonb_array_elements(p_rows) r where upper(btrim(r->>'tableName'))=btrim(d."Table_Name"));
  for item in select value from jsonb_array_elements(p_rows) loop
    n:=upper(btrim(item->>'tableName'));
    if n<>'ALL' and coalesce(upper(btrim(item->>'limitType')),'') not in ('MINIMUM','MAXIMUM') then raise exception 'Select Minimum or Maximum for the limiting table' using errcode='23514'; end if;
    insert into "Basic_Carrier_Record"."Aircraft_Limiting_Weights"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Limit_Condition","Limit_Condition_Code","Limit_From_Date","Limit_To_Date","Limit_Type") values(p_iata,tc,st,n,nullif(btrim(item->>'limitCondition'),''),nullif(upper(btrim(item->>'limitConditionCode')),''),nullif(item->>'limitFromDate','')::date,nullif(item->>'limitToDate','')::date,nullif(upper(btrim(item->>'limitType')),'')) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name") do update set "Limit_Condition"=excluded."Limit_Condition","Limit_Condition_Code"=excluded."Limit_Condition_Code","Limit_From_Date"=excluded."Limit_From_Date","Limit_To_Date"=excluded."Limit_To_Date","Limit_Type"=excluded."Limit_Type";
  end loop;
  return "Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st);
end $function$
;
CREATE OR REPLACE FUNCTION "Basic_Carrier_Record".save_aircraft_f1_rows(p_iata text, p_type_code text, p_subtype text, p_revision text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  tc text:=upper(btrim(p_type_code)); st text:=upper(btrim(p_subtype));
  item jsonb; tn text; variant_code text; reg text; z integer; l integer; t integer; r integer; rem text; current_data jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;
  current_data:="Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st);
  if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023'; end if;

  insert into "Basic_Carrier_Record"."Aircraft_Limiting_Weights"
    ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name")
  values(p_iata,tc,st,'ALL') on conflict do nothing;

  delete from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
  where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;

  for item in select value from jsonb_array_elements(p_rows) loop
    tn:=upper(btrim(item->>'tableName'));
    variant_code:=upper(btrim(item->>'variantCode'));
    reg:=nullif(upper(btrim(item->>'registration')),'');
    z:=nullif(item->>'zeroFuelWeight','')::integer;
    l:=nullif(item->>'landingWeight','')::integer;
    t:=nullif(item->>'takeOffWeight','')::integer;
    r:=nullif(item->>'rampTaxiWeight','')::integer;
    rem:=nullif(btrim(item->>'remarks'),'');

    if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Limiting_Weights" d where d."Carrier_IATA"=p_iata and d."Aircraft_Type_IATA"=tc and d."Aircraft_Series_Subtype"=st and d."Table_Name"=tn) then
      raise exception 'Unknown Weight Table Name' using errcode='23503';
    end if;
    if not exists(select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st and v."Carrier_Variant_Code"=variant_code) then
      raise exception 'Unknown Series/Sub-Series' using errcode='23503';
    end if;
    if reg is not null and not exists(
      select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f
      where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st
        and upper(btrim(f."Carrier_Variant_Code"))=variant_code and upper(btrim(f."Aircraft_Registration"))=reg
    ) then raise exception 'Unknown registration for Series/Sub-Series' using errcode='23503'; end if;

    if tn='ALL' and reg is not null and not exists (
      select 1 from jsonb_array_elements(p_rows) d
      where upper(btrim(d->>'tableName'))='ALL' and upper(btrim(d->>'variantCode'))=variant_code
      and nullif(btrim(d->>'registration'),'') is null
      and z <= (d->>'zeroFuelWeight')::integer and l <= (d->>'landingWeight')::integer
      and t <= (d->>'takeOffWeight')::integer and r <= (d->>'rampTaxiWeight')::integer
    ) then raise exception 'Registration exception requires ALL defaults and cannot exceed them' using errcode='23514'; end if;
    insert into "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
      ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Carrier_Variant_Code","Aircraft_Registration",
       "Zero_Fuel_Weight","Landing_Weight","Take_Off_Weight","Ramp_Taxi_Weight","Remarks")
    values(p_iata,tc,st,tn,variant_code,reg,z,l,t,r,rem);
  end loop;
  return "Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st);
end $function$
;
