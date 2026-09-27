begin;

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  drop constraint "Carrier_ULD_Positions_Natural_key",
  drop constraint "Carrier_ULD_Positions_ID_check",
  alter column "ULD_Position_ID" type varchar(6),
  add constraint "Carrier_ULD_Positions_ID_check" check ("ULD_Position_ID" ~ '^[A-Z0-9]{1,6}$'),
  add constraint "Carrier_ULD_Positions_Parent_key" unique
    ("ULD_Position_UUID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code");

create unique index "Carrier_ULD_Positions_Arrangement_key"
  on "Basic_Carrier_Record"."Carrier_ULD_Positions"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","ULD_Row_Type","ULD_Position_ID",coalesce("ULD_Type",''));

create table "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Hold_Name_ID" varchar(3) not null,
  "ULD_Configuration_Code" varchar(20) not null,
  "Atomic_Bay_ID" varchar(6) not null,
  "Compartment_ID" varchar(3) not null,
  "Lateral_Arm_Centroid" double precision,
  "Lateral_Arm_From" double precision,
  "Lateral_Arm_To" double precision,
  "Balance_Arm_Centroid" double precision not null,
  "Balance_Arm_From" double precision,
  "Balance_Arm_To" double precision,
  "Atomic_Bay_Colour" varchar(7),
  primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Atomic_Bay_ID"),
  constraint "Carrier_ULD_Atomic_Bays_ID_check" check ("Atomic_Bay_ID" ~ '^[A-Z0-9]{1,6}$'),
  constraint "Carrier_ULD_Atomic_Bays_Colour_check" check ("Atomic_Bay_Colour" is null or "Atomic_Bay_Colour" ~ '^#[0-9A-Fa-f]{6}$'),
  constraint "Carrier_ULD_Atomic_Bays_Lateral_check" check (
    ("Lateral_Arm_From" is null and "Lateral_Arm_Centroid" is null and "Lateral_Arm_To" is null)
    or ("Lateral_Arm_From" is not null and "Lateral_Arm_Centroid" is not null and "Lateral_Arm_To" is not null
      and "Lateral_Arm_From" <= "Lateral_Arm_Centroid" and "Lateral_Arm_Centroid" <= "Lateral_Arm_To")
  ),
  constraint "Carrier_ULD_Atomic_Bays_Balance_check" check (
    abs("Balance_Arm_Centroid") <= 1000000 and
    (("Balance_Arm_From" is null and "Balance_Arm_To" is null)
      or ("Balance_Arm_From" is not null and "Balance_Arm_To" is not null
        and "Balance_Arm_From" <= "Balance_Arm_Centroid" and "Balance_Arm_Centroid" <= "Balance_Arm_To"))
  ),
  constraint "Carrier_ULD_Atomic_Bays_Configuration_fkey" foreign key
    ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code")
    references "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
      ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code")
    on update cascade on delete cascade,
  constraint "Carrier_ULD_Atomic_Bays_Compartment_fkey" foreign key
    ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Compartment_ID","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Aircraft_Compartments"
      ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Compartment_ID","Aircraft_Series_Subtype")
    on update cascade on delete restrict
);

create table "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" (
  "ULD_Position_UUID" uuid not null,
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Hold_Name_ID" varchar(3) not null,
  "ULD_Configuration_Code" varchar(20) not null,
  "Atomic_Bay_ID" varchar(6) not null,
  primary key ("ULD_Position_UUID","Atomic_Bay_ID"),
  constraint "Carrier_ULD_Position_Occupancy_Parent_fkey" foreign key
    ("ULD_Position_UUID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code")
    references "Basic_Carrier_Record"."Carrier_ULD_Positions"
      ("ULD_Position_UUID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code")
    on update cascade on delete cascade,
  constraint "Carrier_ULD_Position_Occupancy_Atomic_fkey" foreign key
    ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Atomic_Bay_ID")
    references "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays"
      ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Atomic_Bay_ID")
    on update cascade on delete cascade
);

alter table "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" enable row level security;
alter table "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" enable row level security;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" to authenticated;
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" to authenticated;

create policy perm_aircraft_select on "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" for select to authenticated
using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy perm_aircraft_insert on "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" for insert to authenticated
with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy perm_aircraft_update on "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" for update to authenticated
using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy perm_aircraft_delete on "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" for delete to authenticated
using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

create policy perm_aircraft_select on "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" for select to authenticated
using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy perm_aircraft_insert on "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" for insert to authenticated
with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy perm_aircraft_update on "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" for update to authenticated
using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')))
with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy perm_aircraft_delete on "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" for delete to authenticated
using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));

-- Preserve every existing D3 row as a one-to-one atomic bay and footprint.
insert into "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays"
("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Atomic_Bay_ID","Compartment_ID","Lateral_Arm_Centroid","Lateral_Arm_From","Lateral_Arm_To","Balance_Arm_Centroid","Balance_Arm_From","Balance_Arm_To","Atomic_Bay_Colour")
select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","ULD_Position_ID","Compartment_ID","Lateral_Arm_Centroid","Lateral_Arm_From","Lateral_Arm_To","Balance_Arm_Centroid","Balance_Arm_From","Balance_Arm_To","ULD_Position_Colour"
from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "ULD_Row_Type"='POSITION';

insert into "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy"
("ULD_Position_UUID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Atomic_Bay_ID")
select "ULD_Position_UUID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","ULD_Position_ID"
from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "ULD_Row_Type"='POSITION';

create or replace function "Basic_Carrier_Record".get_aircraft_d3(p_iata text,p_type_code text,p_subtype text) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');holds jsonb;uld_types jsonb;configs jsonb;
begin
if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
select coalesce(jsonb_agg(jsonb_build_object('id',btrim(h."Hold_Name_ID"),'compartments',coalesce((select jsonb_agg(btrim(c."Compartment_ID") order by btrim(c."Compartment_ID")) from "Basic_Carrier_Record"."Aircraft_Compartments" c where c."Carrier_IATA"=h."Carrier_IATA" and c."Aircraft_Type_IATA"=h."Aircraft_Type_IATA" and c."Aircraft_Series_Subtype"=h."Aircraft_Series_Subtype" and c."Hold_Name_ID"=h."Hold_Name_ID"),'[]'::jsonb)) order by btrim(h."Hold_Name_ID")),'[]'::jsonb) into holds from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Type")='ULD';
select coalesce(jsonb_agg(t."ULD_Type" order by t."ULD_Type"),'[]'::jsonb) into uld_types from (select distinct "ULD_Type" from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) t;
select coalesce(jsonb_agg(jsonb_build_object(
 'holdId',c."Hold_Name_ID",'code',c."ULD_Configuration_Code",'description',c."Configuration_Description",'expectedPositionCount',c."Expected_Physical_Positions",
 'atomicBays',coalesce((select jsonb_agg(jsonb_build_object('id',b."Atomic_Bay_ID",'compartmentId',b."Compartment_ID",'lateralCentroid',b."Lateral_Arm_Centroid",'lateralFrom',b."Lateral_Arm_From",'lateralTo',b."Lateral_Arm_To",'balanceCentroid',b."Balance_Arm_Centroid",'balanceFrom',b."Balance_Arm_From",'balanceTo',b."Balance_Arm_To",'colour',b."Atomic_Bay_Colour") order by b."Balance_Arm_Centroid",b."Atomic_Bay_ID") from "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" b where b."Carrier_IATA"=c."Carrier_IATA" and b."Aircraft_Type_IATA"=c."Aircraft_Type_IATA" and b."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype" and b."Hold_Name_ID"=c."Hold_Name_ID" and b."ULD_Configuration_Code"=c."ULD_Configuration_Code"),'[]'::jsonb),
 'rows',coalesce((select jsonb_agg(jsonb_build_object('rowType',p."ULD_Row_Type",'positionId',p."ULD_Position_ID",'compartmentId',p."Compartment_ID",'uldType',p."ULD_Type",'uldBaseCode',p."ULD_Base_Code",'groupId',p."ULD_Group_ID",'occupiedBayIds',coalesce((select jsonb_agg(o."Atomic_Bay_ID" order by o."Atomic_Bay_ID") from "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy" o where o."ULD_Position_UUID"=p."ULD_Position_UUID"),'[]'::jsonb),'maxWeight',p."ULD_Position_Max_Weight",'volume',p."ULD_Position_Volume",'lateralCentroid',p."Lateral_Arm_Centroid",'lateralFrom',p."Lateral_Arm_From",'lateralTo',p."Lateral_Arm_To",'balanceCentroid',p."Balance_Arm_Centroid",'balanceFrom',p."Balance_Arm_From",'balanceTo',p."Balance_Arm_To",'indexPerWeightUnit',p."Index_Per_Weight_Unit",'colour',p."ULD_Position_Colour") order by p."ULD_Position_ID",p."ULD_Type") from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=c."Carrier_IATA" and p."Aircraft_Type_IATA"=c."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype" and p."Hold_Name_ID"=c."Hold_Name_ID" and p."ULD_Configuration_Code"=c."ULD_Configuration_Code"),'[]'::jsonb)
) order by c."Hold_Name_ID",c."ULD_Configuration_Code"),'[]'::jsonb) into configs from "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st;
return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(jsonb_build_object('holds',holds,'uldTypes',uld_types,'configurations',configs)::text),'typeCode',tc,'subtype',st,'uldHolds',holds,'uldTypes',uld_types,'configurations',configs);end$$;

create or replace function "Basic_Carrier_Record".save_aircraft_d3_configuration(p_iata text,p_type_code text,p_subtype text,p_revision text,p_original_code text,p_values jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));hold_id text:=upper(btrim(p_values->>'holdId'));code text:=upper(btrim(p_values->>'code'));original_code text:=nullif(upper(btrim(p_original_code)),'');description text:=nullif(btrim(p_values->>'description'),'');expected smallint;rows_data jsonb;bays_data jsonb;item jsonb;bay_id text;occupied_id text;current_data jsonb;row_type text;compartment_id text;uld_type text;base_code text;position_uuid uuid;
begin
if not(private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
current_data:="Basic_Carrier_Record".get_aircraft_d3(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft D3 changed' using errcode='40001';end if;
if p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'rows')<>'array' or jsonb_typeof(p_values->'atomicBays')<>'array' then raise exception 'Invalid D3 values' using errcode='22023';end if;
expected:=(p_values->>'expectedPositionCount')::smallint;rows_data:=p_values->'rows';bays_data:=p_values->'atomicBays';
if code !~ '^[A-Z0-9][A-Z0-9_-]{0,19}$' or expected not between 1 and 999 or jsonb_array_length(bays_data)<>expected then raise exception 'Invalid D3 configuration' using errcode='22023';end if;
if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id and btrim("Hold_Type")='ULD') then raise exception 'Invalid ULD hold' using errcode='23503';end if;
if original_code is not null and original_code<>code then update "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" set "ULD_Configuration_Code"=code where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "ULD_Configuration_Code"=original_code;if not found then raise exception 'Configuration not found' using errcode='23503';end if;end if;
insert into "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Configuration_Description","Expected_Physical_Positions","Updated_At") values(p_iata,tc,st,hold_id,code,description,expected,now()) on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code") do update set "Configuration_Description"=excluded."Configuration_Description","Expected_Physical_Positions"=excluded."Expected_Physical_Positions","Updated_At"=now();
delete from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "ULD_Configuration_Code"=code;
delete from "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "ULD_Configuration_Code"=code;
for item in select value from jsonb_array_elements(bays_data) loop
 bay_id:=upper(btrim(item->>'id'));compartment_id:=upper(btrim(item->>'compartmentId'));
 if bay_id !~ '^[A-Z0-9]{1,6}$' or not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Compartments" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "Compartment_ID"=compartment_id) then raise exception 'Invalid atomic bay' using errcode='23503';end if;
 insert into "Basic_Carrier_Record"."Carrier_ULD_Atomic_Bays"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Atomic_Bay_ID","Compartment_ID","Lateral_Arm_Centroid","Lateral_Arm_From","Lateral_Arm_To","Balance_Arm_Centroid","Balance_Arm_From","Balance_Arm_To","Atomic_Bay_Colour") values(p_iata,tc,st,hold_id,code,bay_id,compartment_id,nullif(item->>'lateralCentroid','')::double precision,nullif(item->>'lateralFrom','')::double precision,nullif(item->>'lateralTo','')::double precision,(item->>'balanceCentroid')::double precision,nullif(item->>'balanceFrom','')::double precision,nullif(item->>'balanceTo','')::double precision,nullif(item->>'colour',''));
end loop;
for item in select value from jsonb_array_elements(rows_data) loop
 row_type:=coalesce(item->>'rowType','POSITION');compartment_id:=nullif(upper(btrim(item->>'compartmentId')),'');uld_type:=nullif(upper(btrim(item->>'uldType')),'');
 if row_type not in('POSITION','GROUP_LIMIT') then raise exception 'Invalid row type' using errcode='22023';end if;
 if row_type='POSITION' and (jsonb_typeof(item->'occupiedBayIds')<>'array' or jsonb_array_length(item->'occupiedBayIds')=0 or compartment_id is null or not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Compartments" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "Compartment_ID"=compartment_id)) then raise exception 'Select a D2 compartment and occupied Atomic Bays' using errcode='23503';end if;
 if row_type='POSITION' and (uld_type is null or not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "ULD_Type"=uld_type)) then raise exception 'Select a ULD Type configured on B5' using errcode='23503';end if;
 select m."ULD_Base_Code" into base_code from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=s."Master_ULD_ID" where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st and s."ULD_Type"=uld_type limit 1;
 insert into "Basic_Carrier_Record"."Carrier_ULD_Positions"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","ULD_Row_Type","ULD_Position_ID","Compartment_ID","ULD_Type","ULD_Base_Code","ULD_Group_ID","ULD_Position_Max_Weight","ULD_Position_Volume","Lateral_Arm_Centroid","Lateral_Arm_From","Lateral_Arm_To","Balance_Arm_Centroid","Balance_Arm_From","Balance_Arm_To","Index_Per_Weight_Unit","ULD_Position_Colour") values(p_iata,tc,st,hold_id,code,row_type,upper(btrim(item->>'positionId')),case when row_type='POSITION' then compartment_id else null end,case when row_type='POSITION' then uld_type else null end,case when row_type='POSITION' then base_code else null end,nullif(upper(btrim(item->>'groupId')),''),(item->>'maxWeight')::bigint,nullif(item->>'volume','')::bigint,nullif(item->>'lateralCentroid','')::double precision,nullif(item->>'lateralFrom','')::double precision,nullif(item->>'lateralTo','')::double precision,(item->>'balanceCentroid')::double precision,nullif(item->>'balanceFrom','')::double precision,nullif(item->>'balanceTo','')::double precision,nullif(item->>'indexPerWeightUnit','')::double precision,nullif(item->>'colour','')) returning "ULD_Position_UUID" into position_uuid;
 if row_type='POSITION' then for occupied_id in select upper(btrim(value#>>'{}')) from jsonb_array_elements(item->'occupiedBayIds') loop
  insert into "Basic_Carrier_Record"."Carrier_ULD_Position_Occupancy"("ULD_Position_UUID","Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Atomic_Bay_ID") values(position_uuid,p_iata,tc,st,hold_id,code,occupied_id);
 end loop;end if;
end loop;
return "Basic_Carrier_Record".get_aircraft_d3(p_iata,tc,st);end$$;

notify pgrst,'reload schema';
commit;
