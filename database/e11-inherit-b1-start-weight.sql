begin;

create or replace function private.sync_aircraft_start_weight_principle_from_carrier()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  update "Basic_Carrier_Record"."Basic_Aircraft_Data"
  set "Start_Weight_Principle"=case
    when new."Carrier_Basic_Weight" then 'BASIC_WEIGHT'
    when new."Carrier_Dry_Operating_Weight" then 'DRY_OPERATING_WEIGHT'
    else null
  end
  where "Carrier_IATA"=new."Carrier_IATA";
  return new;
end
$$;

revoke all on function private.sync_aircraft_start_weight_principle_from_carrier() from public,anon,authenticated;

drop trigger if exists sync_aircraft_start_weight_principle_from_carrier
on "Basic_Carrier_Record"."Basic_Carrier_Data";
create trigger sync_aircraft_start_weight_principle_from_carrier
after insert or update of "Carrier_Basic_Weight","Carrier_Dry_Operating_Weight"
on "Basic_Carrier_Record"."Basic_Carrier_Data"
for each row execute function private.sync_aircraft_start_weight_principle_from_carrier();

update "Basic_Carrier_Record"."Basic_Aircraft_Data" a
set "Start_Weight_Principle"=case
  when b."Carrier_Basic_Weight" then 'BASIC_WEIGHT'
  when b."Carrier_Dry_Operating_Weight" then 'DRY_OPERATING_WEIGHT'
  else null
end
from "Basic_Carrier_Record"."Basic_Carrier_Data" b
where b."Carrier_IATA"=a."Carrier_IATA"
and a."Start_Weight_Principle" is distinct from case
  when b."Carrier_Basic_Weight" then 'BASIC_WEIGHT'
  when b."Carrier_Dry_Operating_Weight" then 'DRY_OPERATING_WEIGHT'
  else null
end;

create or replace function "Basic_Carrier_Record".save_aircraft_e11(p_iata text,p_type_code text,p_subtype text,p_revision text,p_value jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;principle text;items jsonb:=p_value->'inclusions';item jsonb;item_name text;included boolean;expected_count integer;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_e11(p_iata,tc,st);if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001';end if;
 principle:=current_data->>'principle';
 if principle not in ('BASIC_WEIGHT','DRY_OPERATING_WEIGHT') then raise exception 'Complete the Starting Weight Principle on B1 first' using errcode='23514';end if;
 if jsonb_typeof(items)<>'array' then raise exception 'Inclusions must be an array' using errcode='22023';end if;
 select count(*) into expected_count from "Basic_Carrier_Record"."MASTER_Dry_Operating_Weight_Inclusions";
 if jsonb_array_length(items)<>expected_count then raise exception 'Complete inclusion list required' using errcode='22023';end if;
 if (select count(distinct value->>'item') from jsonb_array_elements(items))<>expected_count then raise exception 'Duplicate or missing inclusion' using errcode='23514';end if;
 update "Basic_Carrier_Record"."Basic_Aircraft_Data" set "Start_Weight_Principle"=principle where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
 for item in select value from jsonb_array_elements(items) loop
  item_name:=btrim(item->>'item');included:=case when item_name='Basic Weight' then true else coalesce((item->>'included')::boolean,false) end;
  if not exists(select 1 from "Basic_Carrier_Record"."MASTER_Dry_Operating_Weight_Inclusions" where "DOW_Item"=item_name) then raise exception 'Unknown inclusion' using errcode='23503';end if;
  insert into "Basic_Carrier_Record"."Carrier_Dry_Operating_Weight_Inclusions"("Carrier_IATA","DOW_Item","Included") values(p_iata,item_name,included)
  on conflict("Carrier_IATA","DOW_Item") do update set "Included"=excluded."Included";
 end loop;
 return "Basic_Carrier_Record".get_aircraft_e11(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".save_aircraft_e11(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_e11(text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
