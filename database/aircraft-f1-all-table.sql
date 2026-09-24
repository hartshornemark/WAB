begin;

create or replace function "Basic_Carrier_Record".save_aircraft_f1_definitions(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
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
    insert into "Basic_Carrier_Record"."Aircraft_Limiting_Weights"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Limit_Condition","Limit_Condition_Code","Limit_From_Date","Limit_To_Date","Limit_Type") values(p_iata,tc,st,n,nullif(btrim(item->>'limitCondition'),''),nullif(upper(btrim(item->>'limitConditionCode')),''),nullif(item->>'limitFromDate','')::date,nullif(item->>'limitToDate','')::date,nullif(upper(btrim(item->>'limitType')),'')) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name") do update set "Limit_Condition"=excluded."Limit_Condition","Limit_Condition_Code"=excluded."Limit_Condition_Code","Limit_From_Date"=excluded."Limit_From_Date","Limit_To_Date"=excluded."Limit_To_Date","Limit_Type"=excluded."Limit_Type";
  end loop;
  return "Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".save_aircraft_f1_definitions(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_f1_definitions(text,text,text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
