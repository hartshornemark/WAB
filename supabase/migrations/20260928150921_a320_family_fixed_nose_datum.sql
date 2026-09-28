-- User-confirmed A320-family datum, 28 September 2026. Applies to all series.
create or replace function "Basic_Carrier_Record".fixed_aircraft_nose_arm(p_type text,p_unit text)
returns numeric language sql immutable set search_path='' as $$
 select case when upper(btrim(p_type)) in ('318','319','320','321','32A','32B','32N','32Q') then
 case upper(p_unit) when 'M' then 2.54 when 'CM' then 254 when 'IN' then 100 when 'FT' then round(100.0/12,6) end end;
$$;
revoke all on function "Basic_Carrier_Record".fixed_aircraft_nose_arm(text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".fixed_aircraft_nose_arm(text,text) to authenticated;

create or replace function "Basic_Carrier_Record".enforce_fixed_nose_arm()
returns trigger language plpgsql set search_path='' as $$
declare fixed_value numeric; unit text;
begin
 if TG_TABLE_NAME='MASTER_Aircraft_Type_IATA' then unit:='M';
 else
 select "Length_Unit" into unit from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"
 where "Carrier_IATA"=new."Carrier_IATA" and "Aircraft_Type_IATA"=new."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype";
 end if;
 fixed_value:="Basic_Carrier_Record".fixed_aircraft_nose_arm(new."Aircraft_Type_IATA",unit);
 if fixed_value is not null then new."Balance_Arm_At_Nose":=fixed_value; end if;
 return new;
end $$;
revoke all on function "Basic_Carrier_Record".enforce_fixed_nose_arm() from public,anon,authenticated;
create trigger enforce_fixed_nose_arm before insert or update on "Basic_Carrier_Record"."Carrier_Basic_Index_MAC"
for each row execute function "Basic_Carrier_Record".enforce_fixed_nose_arm();
create trigger enforce_fixed_nose_arm before insert or update on "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
for each row execute function "Basic_Carrier_Record".enforce_fixed_nose_arm();

create or replace function "Basic_Carrier_Record".sync_fixed_nose_arm_unit()
returns trigger language plpgsql set search_path='' as $$
begin
 if "Basic_Carrier_Record".fixed_aircraft_nose_arm(new."Aircraft_Type_IATA",new."Length_Unit") is not null then
 update "Basic_Carrier_Record"."Carrier_Basic_Index_MAC" set "Balance_Arm_At_Nose"="Basic_Carrier_Record".fixed_aircraft_nose_arm(new."Aircraft_Type_IATA",new."Length_Unit")
 where "Carrier_IATA"=new."Carrier_IATA" and "Aircraft_Type_IATA"=new."Aircraft_Type_IATA" and "Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype";
 end if;
 return new;
end $$;
revoke all on function "Basic_Carrier_Record".sync_fixed_nose_arm_unit() from public,anon,authenticated;
create trigger sync_fixed_nose_arm_unit after insert or update of "Length_Unit" on "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings"
for each row execute function "Basic_Carrier_Record".sync_fixed_nose_arm_unit();

update "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA" set "Balance_Arm_At_Nose"=2.54
where "Basic_Carrier_Record".fixed_aircraft_nose_arm("Aircraft_Type_IATA",'M') is not null;
update "Basic_Carrier_Record"."Carrier_Basic_Index_MAC" c set "Balance_Arm_At_Nose"="Basic_Carrier_Record".fixed_aircraft_nose_arm(c."Aircraft_Type_IATA",u."Length_Unit")
from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" u
where c."Carrier_IATA"=u."Carrier_IATA" and c."Aircraft_Type_IATA"=u."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=u."Aircraft_Series_Subtype"
and "Basic_Carrier_Record".fixed_aircraft_nose_arm(c."Aircraft_Type_IATA",u."Length_Unit") is not null;

-- Preserve the existing permissions, revision checks and formula values.
do $$
declare original text; revised text;
begin
 select pg_get_functiondef('"Basic_Carrier_Record".get_aircraft_c4(text,text,text)'::regprocedure) into original;
 revised:=replace(original,'''datum'',coalesce(row_data."Balance_Arm_At_Nose",master_datum,0)',
 '''datum'',coalesce("Basic_Carrier_Record".fixed_aircraft_nose_arm(tc,length_unit),row_data."Balance_Arm_At_Nose",master_datum,0)');
 if revised=original then raise exception 'C4 datum expression changed; review required'; end if;
 revised:=replace(revised,'''typeCode'',tc,''subtype'',st,''lengthUnit'',length_unit,',
 '''typeCode'',tc,''subtype'',st,''lengthUnit'',length_unit,''datumLocked'',"Basic_Carrier_Record".fixed_aircraft_nose_arm(tc,length_unit) is not null,');
 execute revised;
end $$;
