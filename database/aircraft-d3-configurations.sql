begin;

create table "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Hold_Name_ID" varchar(1) not null,
  "ULD_Configuration_Code" varchar(20) not null,
  "Configuration_Description" varchar(80),
  "Expected_Physical_Positions" smallint not null,
  "Updated_At" timestamptz not null default now(),
  constraint "Carrier_ULD_Position_Configurations_pkey" primary key
    ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code"),
  constraint "Carrier_ULD_Position_Configurations_Hold_fkey" foreign key
    ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Aircraft_Holds"
    ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    on update cascade on delete cascade,
  constraint "Carrier_ULD_Position_Configurations_Carrier_check" check ("Carrier_IATA" ~ '^[A-Z0-9]{2}$'),
  constraint "Carrier_ULD_Position_Configurations_Type_check" check ("Aircraft_Type_IATA" ~ '^[A-Z0-9]{3}$'),
  constraint "Carrier_ULD_Position_Configurations_Subtype_check" check (char_length("Aircraft_Series_Subtype") between 1 and 4),
  constraint "Carrier_ULD_Position_Configurations_Hold_check" check ("Hold_Name_ID" ~ '^[A-Z0-9]$'),
  constraint "Carrier_ULD_Position_Configurations_Code_check" check ("ULD_Configuration_Code" ~ '^[A-Z0-9][A-Z0-9_-]{0,19}$'),
  constraint "Carrier_ULD_Position_Configurations_Description_check" check ("Configuration_Description" is null or (char_length(btrim("Configuration_Description")) between 1 and 80 and "Configuration_Description"=btrim("Configuration_Description"))),
  constraint "Carrier_ULD_Position_Configurations_Count_check" check ("Expected_Physical_Positions" between 1 and 999)
);

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  add column "ULD_Row_Type" varchar(11) not null default 'POSITION',
  add constraint "Carrier_ULD_Positions_Row_Type_check" check ("ULD_Row_Type" in ('POSITION','GROUP_LIMIT'));

alter table "Basic_Carrier_Record"."Carrier_ULD_Positions"
  drop constraint "Carrier_ULD_Positions_Hold_fkey",
  add constraint "Carrier_ULD_Positions_Hold_fkey" foreign key
    ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Aircraft_Holds"
    ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype")
    on update cascade on delete cascade,
  add constraint "Carrier_ULD_Positions_Configuration_fkey" foreign key
    ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code")
    references "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
    ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code")
    on update cascade on delete cascade;

create index "Carrier_ULD_Positions_Configuration_idx" on "Basic_Carrier_Record"."Carrier_ULD_Positions"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code");
create index "Carrier_ULD_Position_Configurations_Hold_idx" on "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
  ("Carrier_IATA","Aircraft_Type_IATA","Hold_Name_ID","Aircraft_Series_Subtype");

alter table "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" enable row level security;

create policy "perm_aircraft_select" on "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
 for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
 for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_update" on "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
 for update to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"
 for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" to authenticated;

create policy "perm_aircraft_select" on "Basic_Carrier_Record"."Carrier_ULD_Positions"
 for select to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW')) or (select private.has_global_permission('AIRCRAFT_CONFIG_VIEW')));
create policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Carrier_ULD_Positions"
 for insert to authenticated with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_update" on "Basic_Carrier_Record"."Carrier_ULD_Positions"
 for update to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))) with check ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
create policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Carrier_ULD_Positions"
 for delete to authenticated using ((select private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_DELETE')) or (select private.has_global_permission('AIRCRAFT_CONFIG_EDIT')));
grant select,insert,update,delete on "Basic_Carrier_Record"."Carrier_ULD_Positions" to authenticated;

create or replace function "Basic_Carrier_Record".get_aircraft_d3(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');holds jsonb;configs jsonb;
begin
 if not can_view then raise exception 'Not authorised' using errcode='42501';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',btrim(h."Hold_Name_ID")) order by btrim(h."Hold_Name_ID")),'[]'::jsonb) into holds from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Type")='ULD';
 select coalesce(jsonb_agg(jsonb_build_object('holdId',c."Hold_Name_ID",'code',c."ULD_Configuration_Code",'description',c."Configuration_Description",'expectedPositionCount',c."Expected_Physical_Positions",'rows',coalesce((select jsonb_agg(jsonb_build_object('rowType',p."ULD_Row_Type",'positionId',p."ULD_Position_ID",'groupId',p."ULD_Group_ID",'maxWeight',p."ULD_Position_Max_Weight",'volume',p."ULD_Position_Volume",'lateralCentroid',p."Lateral_Arm_Centroid",'lateralFrom',p."Lateral_Arm_From",'lateralTo',p."Lateral_Arm_To",'balanceCentroid',p."Balance_Arm_Centroid",'balanceFrom',p."Balance_Arm_From",'balanceTo',p."Balance_Arm_To",'indexPerWeightUnit',p."Index_Per_Weight_Unit",'colour',p."ULD_Position_Colour") order by p."ULD_Position_ID") from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=c."Carrier_IATA" and p."Aircraft_Type_IATA"=c."Aircraft_Type_IATA" and p."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype" and p."Hold_Name_ID"=c."Hold_Name_ID" and p."ULD_Configuration_Code"=c."ULD_Configuration_Code"),'[]'::jsonb)) order by c."Hold_Name_ID",c."ULD_Configuration_Code"),'[]'::jsonb) into configs from "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" c where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st;
 return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(jsonb_build_object('holds',holds,'configurations',configs)::text),'typeCode',tc,'subtype',st,'uldHolds',holds,'configurations',configs);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_d3_configuration(p_iata text,p_type_code text,p_subtype text,p_revision text,p_original_code text,p_values jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));hold_id text:=upper(btrim(p_values->>'holdId'));code text:=upper(btrim(p_values->>'code'));original_code text:=nullif(upper(btrim(p_original_code)),'');description text:=nullif(btrim(p_values->>'description'),'');expected smallint;rows_data jsonb;item jsonb;current_data jsonb;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_d3(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft D3 changed' using errcode='40001';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object' or jsonb_typeof(p_values->'rows')<>'array' then raise exception 'Invalid D3 values' using errcode='22023';end if;
 expected:=(p_values->>'expectedPositionCount')::smallint;rows_data:=p_values->'rows';
 if code !~ '^[A-Z0-9][A-Z0-9_-]{0,19}$' or expected not between 1 and 999 then raise exception 'Invalid D3 configuration' using errcode='22023';end if;
 if not exists(select 1 from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id and btrim("Hold_Type")='ULD') then raise exception 'Invalid ULD hold' using errcode='23503';end if;
 if original_code is not null and original_code<>code then update "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" set "ULD_Configuration_Code"=code where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "ULD_Configuration_Code"=original_code;if not found then raise exception 'Configuration not found' using errcode='23503';end if;end if;
 insert into "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","Configuration_Description","Expected_Physical_Positions","Updated_At") values(p_iata,tc,st,hold_id,code,description,expected,now()) on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code") do update set "Configuration_Description"=excluded."Configuration_Description","Expected_Physical_Positions"=excluded."Expected_Physical_Positions","Updated_At"=now();
 delete from "Basic_Carrier_Record"."Carrier_ULD_Positions" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=hold_id and "ULD_Configuration_Code"=code;
 for item in select value from jsonb_array_elements(rows_data) loop
  insert into "Basic_Carrier_Record"."Carrier_ULD_Positions"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","ULD_Configuration_Code","ULD_Row_Type","ULD_Position_ID","ULD_Group_ID","ULD_Position_Max_Weight","ULD_Position_Volume","Lateral_Arm_Centroid","Lateral_Arm_From","Lateral_Arm_To","Balance_Arm_Centroid","Balance_Arm_From","Balance_Arm_To","Index_Per_Weight_Unit","ULD_Position_Colour") values(p_iata,tc,st,hold_id,code,coalesce(item->>'rowType','POSITION'),upper(btrim(item->>'positionId')),nullif(upper(btrim(item->>'groupId')),''),(item->>'maxWeight')::bigint,nullif(item->>'volume','')::bigint,nullif(item->>'lateralCentroid','')::double precision,nullif(item->>'lateralFrom','')::double precision,nullif(item->>'lateralTo','')::double precision,(item->>'balanceCentroid')::double precision,nullif(item->>'balanceFrom','')::double precision,nullif(item->>'balanceTo','')::double precision,nullif(item->>'indexPerWeightUnit','')::double precision,nullif(item->>'colour',''));
 end loop;
 return "Basic_Carrier_Record".get_aircraft_d3(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".delete_aircraft_d3_configuration(p_iata text,p_type_code text,p_subtype text,p_revision text,p_hold_id text,p_code text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;
begin
 if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501';end if;
 perform 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st for update;if not found then raise exception 'Aircraft not found' using errcode='23503';end if;
 current_data:="Basic_Carrier_Record".get_aircraft_d3(p_iata,tc,st);if p_revision is distinct from current_data->>'revision' then raise exception 'Aircraft D3 changed' using errcode='40001';end if;
 delete from "Basic_Carrier_Record"."Carrier_ULD_Position_Configurations" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Hold_Name_ID"=upper(btrim(p_hold_id)) and "ULD_Configuration_Code"=upper(btrim(p_code));
 return "Basic_Carrier_Record".get_aircraft_d3(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_d3(text,text,text),"Basic_Carrier_Record".save_aircraft_d3_configuration(text,text,text,text,text,jsonb),"Basic_Carrier_Record".delete_aircraft_d3_configuration(text,text,text,text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d3(text,text,text),"Basic_Carrier_Record".save_aircraft_d3_configuration(text,text,text,text,text,jsonb),"Basic_Carrier_Record".delete_aircraft_d3_configuration(text,text,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
