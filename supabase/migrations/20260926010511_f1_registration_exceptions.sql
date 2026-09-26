-- Preserve ALL defaults while allowing registration-specific lower limits.
ALTER TABLE "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" DROP CONSTRAINT "Aircraft_Limiting_Weight_Values_scope_check";
ALTER TABLE "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" ADD CONSTRAINT "Aircraft_Limiting_Weight_Values_scope_check"
CHECK (("Table_Name"='ALL' AND "Aircraft_Registration" IS NULL) OR ("Aircraft_Registration" IS NOT NULL AND btrim("Aircraft_Registration") ~ '^[A-Z0-9][A-Z0-9-]{0,9}$'));
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
    if (tn<>'ALL' or reg is not null) and not exists(
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
