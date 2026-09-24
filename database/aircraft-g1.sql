begin;

alter table "Basic_Carrier_Record"."Aircraft_ULD_Compatibility"
  alter column "Carrier_IATA" type varchar(2),
  alter column "Aircraft_Type_IATA" type varchar(3),
  alter column "Aircraft_Series_SubType" type varchar(4),
  alter column "Bay_ID" type varchar(3),
  alter column "ULD_Type" type varchar(6);

do $$ begin
  if not exists(select 1 from pg_constraint where conname='Aircraft_ULD_Compatibility_aircraft_fkey') then
    alter table "Basic_Carrier_Record"."Aircraft_ULD_Compatibility"
      add constraint "Aircraft_ULD_Compatibility_aircraft_fkey" foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType")
      references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update cascade on delete cascade;
  end if;
  if not exists(select 1 from pg_constraint where conname='Aircraft_ULD_Compatibility_pair_key') then
    alter table "Basic_Carrier_Record"."Aircraft_ULD_Compatibility"
      add constraint "Aircraft_ULD_Compatibility_pair_key" unique("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType","Bay_ID","ULD_Type");
  end if;
  if not exists(select 1 from pg_constraint where conname='Aircraft_ULD_Compatibility_Bay_check') then
    alter table "Basic_Carrier_Record"."Aircraft_ULD_Compatibility"
      add constraint "Aircraft_ULD_Compatibility_Bay_check" check("Bay_ID"=upper(btrim("Bay_ID")) and char_length(btrim("Bay_ID")) between 1 and 3);
  end if;
  if not exists(select 1 from pg_constraint where conname='Aircraft_ULD_Compatibility_Type_check') then
    alter table "Basic_Carrier_Record"."Aircraft_ULD_Compatibility"
      add constraint "Aircraft_ULD_Compatibility_Type_check" check("ULD_Type"=upper(btrim("ULD_Type")) and char_length(btrim("ULD_Type")) between 1 and 6);
  end if;
end $$;

alter table "Basic_Carrier_Record"."Aircraft_ULD_Compatibility" enable row level security;
drop policy if exists "perm_aircraft_select" on "Basic_Carrier_Record"."Aircraft_ULD_Compatibility";
drop policy if exists "perm_aircraft_insert" on "Basic_Carrier_Record"."Aircraft_ULD_Compatibility";
drop policy if exists "perm_aircraft_update" on "Basic_Carrier_Record"."Aircraft_ULD_Compatibility";
drop policy if exists "perm_aircraft_delete" on "Basic_Carrier_Record"."Aircraft_ULD_Compatibility";
create policy "perm_aircraft_select" on "Basic_Carrier_Record"."Aircraft_ULD_Compatibility" for select to authenticated using(private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
create policy "perm_aircraft_insert" on "Basic_Carrier_Record"."Aircraft_ULD_Compatibility" for insert to authenticated with check(private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT'));
create policy "perm_aircraft_update" on "Basic_Carrier_Record"."Aircraft_ULD_Compatibility" for update to authenticated using(private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) with check(private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT'));
create policy "perm_aircraft_delete" on "Basic_Carrier_Record"."Aircraft_ULD_Compatibility" for delete to authenticated using(private.has_carrier_permission("Carrier_IATA",'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT'));
grant select,insert,update,delete on "Basic_Carrier_Record"."Aircraft_ULD_Compatibility" to authenticated;

create or replace function "Basic_Carrier_Record".get_aircraft_g1(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ci text:=upper(btrim(p_iata));tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean;can_edit boolean;applicable boolean;bays jsonb;uld_types jsonb;compatibilities jsonb;suggestions jsonb;
begin
  can_view:=private.has_carrier_permission(ci,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW');
  can_edit:=private.has_carrier_permission(ci,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=ci and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503'; end if;
  select c."ULD_Holds_Applicable" into applicable from "Basic_Carrier_Record"."Aircraft_Hold_Configuration" c where c."Carrier_IATA"=ci and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(jsonb_build_object('holdId',x.hold_id,'bayId',x.bay_id) order by x.hold_id,x.bay_id),'[]'::jsonb) into bays from (
    select distinct btrim(p."Hold_Name_ID") hold_id,btrim(p."ULD_Position_ID") bay_id
    from "Basic_Carrier_Record"."Carrier_ULD_Positions" p
    where p."Carrier_IATA"=ci and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."ULD_Row_Type"='POSITION'
  ) x;
  select coalesce(jsonb_agg(x.uld_type order by x.uld_type),'[]'::jsonb) into uld_types from (
    select distinct btrim(s."ULD_Type") uld_type from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s
    where s."Carrier_IATA"=ci and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('bayId',btrim(c."Bay_ID"),'uldType',btrim(c."ULD_Type"),'compatible',c."ULD_Compatibility") order by btrim(c."Bay_ID"),btrim(c."ULD_Type")),'[]'::jsonb) into compatibilities
  from "Basic_Carrier_Record"."Aircraft_ULD_Compatibility" c
  where c."Carrier_IATA"=ci and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_SubType"=st
    and exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=ci and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Position_ID")=btrim(c."Bay_ID"))
    and exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s where s."Carrier_IATA"=ci and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st and btrim(s."ULD_Type")=btrim(c."ULD_Type"));
  select coalesce(jsonb_agg(jsonb_build_object('bayId',x.bay_id,'uldType',x.uld_type,'compatible',x.bay_base_code is not null and x.uld_base_code is not null and x.bay_base_code=x.uld_base_code) order by x.bay_id,x.uld_type),'[]'::jsonb) into suggestions from (
    select b.bay_id,b.bay_base_code,u.uld_type,u.uld_base_code from
      (select btrim(p."ULD_Position_ID") bay_id,max(btrim(p."ULD_Base_Code")) bay_base_code from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=ci and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."ULD_Row_Type"='POSITION' group by btrim(p."ULD_Position_ID")) b
      cross join
      (select btrim(s."ULD_Type") uld_type,max(btrim(m."ULD_Base_Code")) uld_base_code from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s left join "Basic_Carrier_Record"."MASTER_ULD_List" m on m."ULD_ID"=s."Master_ULD_ID" where s."Carrier_IATA"=ci and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st group by btrim(s."ULD_Type")) u
  ) x;
  return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(jsonb_build_object('applicable',applicable,'bays',bays,'uldTypes',uld_types,'rows',compatibilities,'suggestions',suggestions)::text),'typeCode',tc,'subtype',st,'applicable',applicable,'bays',bays,'uldTypes',uld_types,'rows',compatibilities,'suggestions',suggestions);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_g1(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ci text:=upper(btrim(p_iata));tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));item jsonb;expected_count integer;bay_id text;uld_type text;
begin
  if not (private.has_carrier_permission(ci,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_g1(ci,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if coalesce((select c."ULD_Holds_Applicable" from "Basic_Carrier_Record"."Aircraft_Hold_Configuration" c where c."Carrier_IATA"=ci and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st),false) is not true then raise exception 'G1 is not applicable' using errcode='22023'; end if;
  select count(*) into expected_count from (select distinct btrim(p."ULD_Position_ID") bay_id from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=ci and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."ULD_Row_Type"='POSITION') b cross join (select distinct btrim(s."ULD_Type") uld_type from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s where s."Carrier_IATA"=ci and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st) u;
  if expected_count=0 or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<>expected_count then raise exception 'Complete every compatibility value' using errcode='22023'; end if;
  if (select count(*) from (select upper(btrim(value->>'bayId')) bay_id,upper(btrim(value->>'uldType')) uld_type from jsonb_array_elements(p_rows) group by 1,2) x)<>expected_count then raise exception 'Duplicate compatibility value' using errcode='23505'; end if;
  delete from "Basic_Carrier_Record"."Aircraft_ULD_Compatibility" where "Carrier_IATA"=ci and "Aircraft_Type_IATA"=tc and "Aircraft_Series_SubType"=st;
  for item in select value from jsonb_array_elements(p_rows) loop
    bay_id:=upper(btrim(item->>'bayId'));uld_type:=upper(btrim(item->>'uldType'));
    if jsonb_typeof(item->'compatible')<>'boolean' then raise exception 'Compatibility must be true or false' using errcode='22023'; end if;
    if not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Positions" p where p."Carrier_IATA"=ci and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."ULD_Row_Type"='POSITION' and btrim(p."ULD_Position_ID")=bay_id) then raise exception 'Invalid Bay' using errcode='23503'; end if;
    if not exists(select 1 from "Basic_Carrier_Record"."Carrier_ULD_Specifications" s where s."Carrier_IATA"=ci and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st and btrim(s."ULD_Type")=uld_type) then raise exception 'Invalid ULD Type' using errcode='23503'; end if;
    insert into "Basic_Carrier_Record"."Aircraft_ULD_Compatibility"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_SubType","Bay_ID","ULD_Type","ULD_Compatibility") values(ci,tc,st,bay_id,uld_type,(item->>'compatible')::boolean);
  end loop;
  return "Basic_Carrier_Record".get_aircraft_g1(ci,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_g1(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_g1(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_g1(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_g1(text,text,text,text,jsonb) to authenticated;

commit;
