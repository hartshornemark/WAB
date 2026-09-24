begin;

alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications"
  drop constraint if exists uld_optional_master_reference,
  drop constraint if exists uld_type_format,
  drop column "Master_ULD_Type";

alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications"
  alter column "ULD_Type" type varchar(6),
  add column "Master_ULD_Type" varchar(6) generated always as
    (case when not "Is_Custom" then "ULD_Type" else null end) stored;

update "Basic_Carrier_Record"."MASTER_ULD_List"
set "ULD_Type"='LD3-45'
where "ULD_ID"='AKH';

update "Basic_Carrier_Record"."Carrier_ULD_Specifications"
set "ULD_Type"='LD3-45'
where "ULD_ID"='AKH' and not "Is_Custom";

set constraints all immediate;

alter table "Basic_Carrier_Record"."Carrier_ULD_Specifications"
  add constraint uld_type_format check ("ULD_Type" ~ '^[A-Z0-9][A-Z0-9-]{0,5}$'),
  add constraint uld_optional_master_reference foreign key ("Master_ULD_ID","Master_ULD_Type")
    references "Basic_Carrier_Record"."MASTER_ULD_List"("ULD_ID","ULD_Type") on update restrict on delete restrict;

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  add column "ULD_Type" varchar(6),
  add constraint "Carrier_ULD_Positions_ULD_Type_check"
    check ("ULD_Type" is null or "ULD_Type" ~ '^[A-Z0-9][A-Z0-9-]{0,5}$');

create or replace function "Basic_Carrier_Record".get_aircraft_d3(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');holds jsonb;uld_types jsonb;configs jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim(h."Hold_Name_ID")) order by btrim(h."Hold_Name_ID")),'[]'::jsonb) into holds from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Type")='ULD';
 select coalesce(jsonb_agg(t."ULD_Type" order by t."ULD_Type"),'[]'::jsonb) into uld_types from (select distinct "ULD_Type" from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) t;
 select coalesce(jsonb_agg(jsonb_build_object('holdId',c."Hold_Name_ID",'code',c."ULD_Configuration_Code",'description',c."Configuration_Description",'expectedPositionCount',c."Expected_Physical_Positions",'rows',coalesce((select jsonb_agg(jsonb_build_object('rowType',p."ULD_Row_Type",'positionId',p."ULD_Position_ID",'uldType',p."ULD_Type",'groupId',p."ULD_Group_ID",'maxWeight',p."ULD_Position_Max_Weight",'volume',p."ULD_Position_Volume",'lateralCentroid',p."Lateral_Arm_Centroid",'lateralFrom',p."Lateral_Arm_From",'lateralTo',p."Lateral_Arm_To",'balanceCentroid',p."Balance_Arm_Centroid",'balanceFrom',p."Balance_Arm_From",'balanceTo',p."Balance_Arm_To",'indexPerWeightUnit',p."Index_Per_Weight_Unit",'colour',p."ULD_Position_Colour") order by p."ULD_Position_ID") from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=c."Carrier_IATA" and p."Aircraft_Type_IATA"=c."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype" and p."Hold_Name_ID"=c."Hold_Name_ID" and p."ULD_Configuration_Code"=c."ULD_Configuration_Code"),'[]'::jsonb)) order by c."Hold_Name_ID",c."ULD_Configuration_Code"),'[]'::jsonb) into configs from "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(jsonb_build_object('holds',holds,'uldTypes',uld_types,'configurations',configs)::text),'typeCode',tc,'subtype',st,'uldHolds',holds,'uldTypes',uld_types,'configurations',configs);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_d3_configuration(p_iata text,p_type_code text,p_subtype text,p_revision text,p_original_code text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));hold_id text:=upper(btrim(p_values->>'holdId'));code text:=upper(btrim(p_values->>'code'));original_code text:=nullif(upper(btrim(p_original_code)),'');description text:=nullif(btrim(p_values->>'description'),'');expected smallint;rows_data jsonb;item jsonb;current_data jsonb;row_type text;uld_type text;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_d3(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft D3 changed' using errcode='40001';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'rows')<>'array' then raise exception 'Invalid D3 values' using errcode='22023';end if;
 expected:=(p_values->>'expectedPositionCount')::smallint;rows_data:=p_values->'rows';
 if code !~ '^[A-Z0-9][A-Z0-9_-]{0,19}$' or expected not between 1 and 999 then raise exception 'Invalid D3 configuration' using errcode='22023';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id and btrim("Hold_Type")='ULD') then raise exception 'Invalid ULD hold' using errcode='23503';end if;
 for item in select value from jsonb_array_elements(rows_data) loop
  row_type:=coalesce(item->>'rowType','POSITION');uld_type:=nullif(upper(btrim(item->>'uldType')),'');
  if row_type='POSITION' and (uld_type is null or not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "ULD_Type"=uld_type)) then raise exception 'Select a ULD Type configured on B5' using errcode='23503';end if;
 end loop;
 if original_code is not null and original_code<>code then update "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" set "ULD_Configuration_Code"=code where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "ULD_Configuration_Code"=original_code;if not found then raise exception 'Configuration not found' using errcode='23503';end if;end if;
 insert into "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Configuration_Description","Expected_Physical_Positions","Updated_At") values(p_iata,tc,st,hold_id,code,description,expected,now()) on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code") do update set "Configuration_Description"=excluded."Configuration_Description","Expected_Physical_Positions"=excluded."Expected_Physical_Positions","Updated_At"=now();
 delete from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "ULD_Configuration_Code"=code;
 for item in select value from jsonb_array_elements(rows_data) loop
  row_type:=coalesce(item->>'rowType','POSITION');uld_type:=nullif(upper(btrim(item->>'uldType')),'');
  insert into "Basic_Carrier_Record"."Carrier_ULD_Positions"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","ULD_Row_Type","ULD_Position_ID","ULD_Type","ULD_Group_ID","ULD_Position_Max_Weight","ULD_Position_Volume","Lateral_Arm_Centroid","Lateral_Arm_From","Lateral_Arm_To","Balance_Arm_Centroid","Balance_Arm_From","Balance_Arm_To","Index_Per_Weight_Unit","ULD_Position_Colour") values(p_iata,tc,st,hold_id,code,row_type,upper(btrim(item->>'positionId')),case when row_type='POSITION' then uld_type else null end,nullif(upper(btrim(item->>'groupId')),''),(item->>'maxWeight')::bigint,nullif(item->>'volume','')::bigint,nullif(item->>'lateralCentroid','')::double precision,nullif(item->>'lateralFrom','')::double precision,nullif(item->>'lateralTo','')::double precision,(item->>'balanceCentroid')::double precision,nullif(item->>'balanceFrom','')::double precision,nullif(item->>'balanceTo','')::double precision,nullif(item->>'indexPerWeightUnit','')::double precision,nullif(item->>'colour',''));
 end loop;
 return "Basic_Carrier_Record".get_aircraft_d3(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_carrier_ulds(p_iata text,p_type text,p_subtype text,p_revision text,p_rows jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$declare s jsonb;row jsonb;inventory_row jsonb;k text;v text;begin
if not private.can_edit_carrier_details(p_iata) then raise exception 'Not authorised' using errcode='42501';end if;
perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;if not found then raise exception 'Aircraft unavailable' using errcode='23503';end if;
perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
perform 1 from "Basic_Carrier_Record"."Carrier_ULD_Inventory" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype for update;
s:="Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);if p_revision is distinct from s->>'revision' then raise exception 'ULD settings changed' using errcode='40001';end if;if not (s->>'utilisesUlds')::boolean then raise exception 'B5 is skipped' using errcode='23514';end if;if s->>'weightUnit'='' or s->>'volumeUnit'='' then raise exception 'Save B1 units first' using errcode='23514';end if;
if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>200 then raise exception 'At least one ULD Type is required' using errcode='23514';end if;
for row in select value from jsonb_array_elements(p_rows) loop
 if jsonb_typeof(row) is distinct from 'object' or jsonb_typeof(row->'isDefault') is distinct from 'boolean' or jsonb_typeof(row->'remarks') is distinct from 'string' or char_length(row->>'remarks')>2000 or jsonb_typeof(row->'inventory') is distinct from 'array' or jsonb_array_length(row->'inventory')>100 then raise exception 'Invalid ULD entries' using errcode='22023';end if;
 foreach k in array array['tare','maximum','volume'] loop v:=row->>k;if v is null or v !~ '^[0-9]+([.][0-9]{1,6})?$' then raise exception 'Invalid ULD value' using errcode='22023';end if;end loop;
 if jsonb_typeof(row->'isCustom') is distinct from 'boolean' or coalesce(row->>'code','') !~ '^[A-Z0-9]{3}$' or coalesce(row->>'type','') !~ '^[A-Z0-9][A-Z0-9-]{0,5}$' then raise exception 'Invalid ULD Code or Type' using errcode='22023';end if;
 if not (row->>'isCustom')::boolean and not exists(select 1 from "Basic_Carrier_Record"."MASTER_ULD_List" where "ULD_ID"=row->>'code') then raise exception 'ULD not in master' using errcode='23503';end if;
 for inventory_row in select value from jsonb_array_elements(row->'inventory') loop if jsonb_typeof(inventory_row) is distinct from 'object' or coalesce(inventory_row->>'carrierCode','') !~ '^[A-Z0-9]{2}$' or coalesce(inventory_row->>'serialStart','') !~ '^[0-9]{1,5}$' or coalesce(inventory_row->>'serialEnd','') !~ '^[0-9]{1,5}$' or (inventory_row->>'serialStart')::integer>(inventory_row->>'serialEnd')::integer then raise exception 'Invalid ULD inventory range' using errcode='22023';end if;end loop;
end loop;
delete from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype;
insert into "Basic_Carrier_Record"."Carrier_ULD_Specifications"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID","ULD_Type","Is_Custom","ULD_Default","ULD_Tare_Weight","ULD_Max_Weight","ULD_Max_Volume","Remarks") select p_iata,p_type,p_subtype,r->>'code',case when (r->>'isCustom')::boolean then r->>'type' else m."ULD_Type" end,(r->>'isCustom')::boolean,(r->>'isDefault')::boolean,(r->>'tare')::numeric,(r->>'maximum')::numeric,(r->>'volume')::numeric,nullif(r->>'remarks','') from jsonb_array_elements(p_rows) r left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=r->>'code';
if exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype group by "ULD_Type" having count(*) filter(where "ULD_Default")<>1) then raise exception 'Choose one default per ULD type' using errcode='23514';end if;
insert into "Basic_Carrier_Record"."Carrier_ULD_Inventory"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","ULD_ID","ULD_IATA","ULD_Serial_Start","ULD_Serial_End") select p_iata,p_type,p_subtype,r->>'code',i->>'carrierCode',lpad(i->>'serialStart',5,'0'),lpad(i->>'serialEnd',5,'0') from jsonb_array_elements(p_rows) r cross join lateral jsonb_array_elements(r->'inventory') i;
return "Basic_Carrier_Record".get_carrier_ulds(p_iata,p_type,p_subtype);end$$;

notify pgrst,'reload schema';
commit;
