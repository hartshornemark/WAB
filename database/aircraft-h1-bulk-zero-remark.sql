begin;

update "Basic_Carrier_Record"."Aircraft_Special_Load_Limits" l
set "Remarks"='Not Permitted This Hold'
from "Basic_Carrier_Record"."Aircraft_Holds" h
where l."Maximum_Quantity"=0
  and h."Carrier_IATA"=l."Carrier_IATA"
  and h."Aircraft_Type_IATA"=l."Aircraft_Type_IATA"
  and h."Aircraft_Series_Subtype"=l."Aircraft_Series_Subtype"
  and h."Hold_Name_ID"=l."Hold_Name_ID"
  and btrim(h."Hold_Type")='BLK';

create or replace function "Basic_Carrier_Record".save_aircraft_h1_special_loads(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;row_uld boolean;loc text;hold_id text;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_h1(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023'; end if;
  delete from "Basic_Carrier_Record"."Aircraft_Special_Load_Limits" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
  for item in select value from jsonb_array_elements(p_rows) loop
    hold_id:=upper(btrim(item->>'holdId'));loc:=nullif(upper(btrim(item->>'locationRef')),'');
    select btrim(h."Hold_Type")<>'BLK' into row_uld from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Name_ID")=hold_id;
    if row_uld is null then raise exception 'Invalid hold' using errcode='23503'; end if;
    if loc is not null and ((row_uld and not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and btrim(p."Hold_Name_ID")=hold_id and btrim(p."ULD_Position_ID")=loc and p."ULD_Row_Type"='POSITION')) or (not row_uld and not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Compartments" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and btrim(c."Hold_Name_ID")=hold_id and btrim(c."Compartment_ID")=loc))) then raise exception 'Invalid location' using errcode='23503'; end if;
    insert into "Basic_Carrier_Record"."Aircraft_Special_Load_Limits"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","Special_Load_Code","Location_Type","Location_Reference","Maximum_Quantity","Remarks") values(p_iata,tc,st,hold_id,upper(btrim(item->>'code')),case when loc is null then null when row_uld then 'POSITION' else 'COMPARTMENT' end,loc,(item->>'maximumQuantity')::integer,case when not row_uld and (item->>'maximumQuantity')::integer=0 then 'Not Permitted This Hold' when not row_uld and nullif(btrim(item->>'remarks'),'')='Not Permitted This Hold' then null else nullif(btrim(item->>'remarks'),'') end);
  end loop;
  return "Basic_Carrier_Record".get_aircraft_h1(p_iata,tc,st);
end $$;

commit;
