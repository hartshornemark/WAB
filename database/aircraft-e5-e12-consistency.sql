begin;

create or replace function "Basic_Carrier_Record".save_aircraft_e12_standard(p_iata text,p_type_code text,p_subtype text,p_revision text,p_value jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;w integer;i double precision;p text;a text;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 w:=nullif(p_value->>'standardFleetWeight','')::integer;i:=nullif(p_value->>'standardFleetIndex','')::double precision;if w is not null and w<=0 then raise exception 'Invalid SFW' using errcode='23514';end if;if i is not null and abs(i)>1000000000 then raise exception 'Invalid SFI' using errcode='23514';end if;
 select "Start_Weight_Principle","Weight_Recording_Approach" into p,a from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Standard_Fleet_Weight"=w,"Standard_Fleet_Index"=i where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 if a='FLEET_WEIGHTS' and w is not null and i is not null then
  update "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" set "Dry_Operating_Weight"=case when p='DRY_OPERATING_WEIGHT' and "Fleet_Weight_Adjustment" is not null then w+"Fleet_Weight_Adjustment" else "Dry_Operating_Weight" end,"Dry_Operating_Index"=case when p='DRY_OPERATING_WEIGHT' and "Fleet_Index_Adjustment" is not null then i+"Fleet_Index_Adjustment" else "Dry_Operating_Index" end,"Basic_Weight"=case when p='BASIC_WEIGHT' and "Fleet_Weight_Adjustment" is not null then w+"Fleet_Weight_Adjustment" else "Basic_Weight" end,"Basic_Index"=case when p='BASIC_WEIGHT' and "Fleet_Index_Adjustment" is not null then i+"Fleet_Index_Adjustment" else "Basic_Index" end where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference";
 end if;
 return "Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_e12_registrations(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;p text;a text;fw integer;fi double precision;item jsonb;reg text;w integer;i double precision;regs text[]:='{}';
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;if jsonb_typeof(p_rows)<>'array' then raise exception 'Rows required' using errcode='22023';end if;p:=current_data->>'principle';
 select "Weight_Recording_Approach","Standard_Fleet_Weight","Standard_Fleet_Index" into a,fw,fi from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
 for item in select value from jsonb_array_elements(p_rows) loop
  reg:=upper(btrim(item->>'registration'));w:=nullif(item->>'weight','')::integer;i:=nullif(item->>'index','')::double precision;
  if reg !~ '^[A-Z0-9][A-Z0-9-]{0,9}$' or (w is not null and w<=0) or (i is not null and abs(i)>1000000000) then raise exception 'Invalid registration row' using errcode='23514';end if;regs:=array_append(regs,reg);
  update "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" set "Dry_Operating_Weight"=case when p='DRY_OPERATING_WEIGHT' then w else null end,"Dry_Operating_Index"=case when p='DRY_OPERATING_WEIGHT' then i else null end,"Basic_Weight"=case when p='BASIC_WEIGHT' then w else null end,"Basic_Index"=case when p='BASIC_WEIGHT' then i else null end,"Fleet_Weight_Adjustment"=case when a='FLEET_WEIGHTS' and w is not null and fw is not null then w-fw else "Fleet_Weight_Adjustment" end,"Fleet_Index_Adjustment"=case when a='FLEET_WEIGHTS' and i is not null and fi is not null then round((i-fi)::numeric,1)::double precision else "Fleet_Index_Adjustment" end where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference" and btrim("Aircraft_Registration")=reg;
  if not found then insert into "Basic_Carrier_Record"."Carrier_Aircraft_Fleet"("Aircraft_Registration","Carrier_IATA","Aircraft_Type_IATA","Crew_Code_ID","Pantry_Code_ID","Dry_Operating_Weight","Dry_Operating_Index","Aircraft_Series_Subtype","Basic_Weight","Basic_Index","E1_2_Registration_Reference","Fleet_Weight_Adjustment","Fleet_Index_Adjustment") values(reg,p_iata,tc,null,null,case when p='DRY_OPERATING_WEIGHT' then w else null end,case when p='DRY_OPERATING_WEIGHT' then i else null end,st,case when p='BASIC_WEIGHT' then w else null end,case when p='BASIC_WEIGHT' then i else null end,true,case when a='FLEET_WEIGHTS' and w is not null and fw is not null then w-fw else null end,case when a='FLEET_WEIGHTS' and i is not null and fi is not null then round((i-fi)::numeric,1)::double precision else null end);end if;
 end loop;
 delete from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "E1_2_Registration_Reference" and not (btrim("Aircraft_Registration")=any(regs));
 return "Basic_Carrier_Record".get_aircraft_e12(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".save_aircraft_e12_standard(text,text,text,text,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_e12_registrations(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_e12_standard(text,text,text,text,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_e12_registrations(text,text,text,text,jsonb) to authenticated;

commit;
