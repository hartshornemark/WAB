begin;

alter table "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
  add column if not exists "Limiting_Weight_Value_UUID" uuid default gen_random_uuid(),
  add column if not exists "Carrier_Variant_Code" varchar(4);

insert into "Basic_Carrier_Record"."Carrier_Aircraft_Variants"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code")
select a."Carrier_IATA",a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype",a."Aircraft_Series_Subtype"
from "Basic_Carrier_Record"."Basic_Aircraft_Data" a
where not exists (
  select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v
  where v."Carrier_IATA"=a."Carrier_IATA"
    and v."Aircraft_Type_IATA"=a."Aircraft_Type_IATA"
    and v."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype"
)
on conflict do nothing;

update "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" w
set "Carrier_Variant_Code"=f."Carrier_Variant_Code"
from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f
where w."Carrier_Variant_Code" is null
  and f."Carrier_IATA"=w."Carrier_IATA"
  and f."Aircraft_Type_IATA"=w."Aircraft_Type_IATA"
  and f."Aircraft_Series_Subtype"=w."Aircraft_Series_Subtype"
  and upper(btrim(f."Aircraft_Registration"))=upper(btrim(w."Aircraft_Registration"));

update "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" w
set "Carrier_Variant_Code"=(
  select min(x."Carrier_Variant_Code")
  from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" x
  where x."Carrier_IATA"=w."Carrier_IATA"
    and x."Aircraft_Type_IATA"=w."Aircraft_Type_IATA"
    and x."Aircraft_Series_Subtype"=w."Aircraft_Series_Subtype"
)
where w."Carrier_Variant_Code" is null;

create temporary table f1_all_values on commit drop as
select
  "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Carrier_Variant_Code",
  max("Zero_Fuel_Weight") "Zero_Fuel_Weight",
  max("Landing_Weight") "Landing_Weight",
  max("Take_Off_Weight") "Take_Off_Weight",
  max("Ramp_Taxi_Weight") "Ramp_Taxi_Weight",
  max("Remarks") "Remarks"
from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
where "Table_Name"='ALL'
group by "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Carrier_Variant_Code";

delete from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" where "Table_Name"='ALL';

alter table "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
  drop constraint if exists "Aircraft_Limiting_Weight_Values_pkey",
  drop constraint if exists "Aircraft_Limiting_Weight_Values_registration_check",
  alter column "Limiting_Weight_Value_UUID" set not null,
  alter column "Carrier_Variant_Code" set not null,
  alter column "Aircraft_Registration" drop not null;

alter table "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
  add constraint "Aircraft_Limiting_Weight_Values_pkey" primary key ("Limiting_Weight_Value_UUID"),
  add constraint "Aircraft_Limiting_Weight_Values_variant_fkey" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code")
    references "Basic_Carrier_Record"."Carrier_Aircraft_Variants"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code")
    on update cascade on delete restrict,
  add constraint "Aircraft_Limiting_Weight_Values_scope_check" check (
    ("Table_Name"='ALL' and "Aircraft_Registration" is null)
    or
    ("Table_Name"<>'ALL' and btrim("Aircraft_Registration") ~ '^[A-Z0-9][A-Z0-9-]{0,9}$')
  );

create unique index "Aircraft_Limiting_Weight_Values_scope_key"
  on "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Carrier_Variant_Code",coalesce("Aircraft_Registration",''));

create index "Aircraft_Limiting_Weight_Values_variant_idx"
  on "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Carrier_Variant_Code");

insert into "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Carrier_Variant_Code","Aircraft_Registration","Zero_Fuel_Weight","Landing_Weight","Take_Off_Weight","Ramp_Taxi_Weight","Remarks")
select "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Carrier_Variant_Code",null,
       "Zero_Fuel_Weight","Landing_Weight","Take_Off_Weight","Ramp_Taxi_Weight","Remarks"
from f1_all_values;

create or replace function "Basic_Carrier_Record".get_aircraft_f1(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code)); st text:=upper(btrim(p_subtype));
  can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
  can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  unit text; mzfw integer; mlaw integer; mtow integer; mrw integer;
  defs jsonb; vals jsonb; regs jsonb; variants jsonb; first_variant text; payload jsonb;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  select a."MZFW",a."MLAW",a."MTOW",a."MRW",coalesce(s."Weight_Unit",'Kg')
    into mzfw,mlaw,mtow,mrw,unit
  from "Basic_Carrier_Record"."Basic_Aircraft_Data" a
  left join "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" s
    using("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
  where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st;
  if not found then raise exception 'Aircraft not found' using errcode='23503'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'tableId',null,'tableName',btrim(d."Table_Name"),'limitCondition',nullif(btrim(d."Limit_Condition"),''),
    'limitConditionCode',nullif(btrim(d."Limit_Condition_Code"),''),'limitFromDate',d."Limit_From_Date",
    'limitToDate',d."Limit_To_Date",'limitType',nullif(btrim(d."Limit_Type"),''),'persisted',true
  ) order by btrim(d."Table_Name")),'[]'::jsonb) into defs
  from "Basic_Carrier_Record"."Aircraft_Limiting_Weights" d
  where d."Carrier_IATA"=p_iata and d."Aircraft_Type_IATA"=tc and d."Aircraft_Series_Subtype"=st;
  if jsonb_array_length(defs)=0 then
    defs:=jsonb_build_array(jsonb_build_object('tableId',null,'tableName','ALL','limitCondition',null,'limitConditionCode',null,'limitFromDate',null,'limitToDate',null,'limitType',null,'persisted',false));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('code',q.code,'label',tc||'-'||q.code) order by q.code),'[]'::jsonb),min(q.code)
    into variants,first_variant
  from (
    select distinct upper(btrim(v."Carrier_Variant_Code")) code
    from "Basic_Carrier_Record"."Carrier_Aircraft_Variants" v
    where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object('registration',q.registration,'variantCode',q.variant_code) order by q.variant_code,q.registration),'[]'::jsonb)
    into regs
  from (
    select distinct upper(btrim(f."Aircraft_Registration")) registration,upper(btrim(f."Carrier_Variant_Code")) variant_code
    from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f
    where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object(
    'rowId',v."Limiting_Weight_Value_UUID",'tableName',btrim(v."Table_Name"),'variantCode',btrim(v."Carrier_Variant_Code"),
    'registration',nullif(btrim(v."Aircraft_Registration"),''),'zeroFuelWeight',v."Zero_Fuel_Weight",
    'landingWeight',v."Landing_Weight",'takeOffWeight',v."Take_Off_Weight",'rampTaxiWeight',v."Ramp_Taxi_Weight",
    'remarks',nullif(btrim(v."Remarks"),''),'persisted',true
  ) order by btrim(v."Table_Name"),btrim(v."Carrier_Variant_Code"),btrim(v."Aircraft_Registration") nulls first),'[]'::jsonb)
    into vals
  from "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values" v
  where v."Carrier_IATA"=p_iata and v."Aircraft_Type_IATA"=tc and v."Aircraft_Series_Subtype"=st;

  if jsonb_array_length(vals)=0 and first_variant is not null then
    vals:=jsonb_build_array(jsonb_build_object(
      'rowId',null,'tableName','ALL','variantCode',first_variant,'registration',null,
      'zeroFuelWeight',mzfw,'landingWeight',mlaw,'takeOffWeight',mtow,'rampTaxiWeight',mrw,'remarks',null,'persisted',false
    ));
  end if;

  payload:=jsonb_build_object('typeCode',tc,'subtype',st,'weightUnit',unit,'definitions',defs,'rows',vals,
    'variantOptions',variants,'registrationOptions',regs,'c5Source',jsonb_build_object('mzfw',mzfw,'mlaw',mlaw,'mtow',mtow,'mrw',mrw));
  return payload||jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(payload::text));
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_f1_rows(p_iata text,p_type_code text,p_subtype text,p_revision text,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code)); st text:=upper(btrim(p_subtype));
  item jsonb; tn text; variant_code text; reg text; z integer; l integer; t integer; r integer; rem text; current_data jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
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
    reg:=case when tn='ALL' then null else nullif(upper(btrim(item->>'registration')),'') end;
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
    if tn<>'ALL' and not exists(
      select 1 from "Basic_Carrier_Record"."Carrier_Aircraft_Fleet" f
      where f."Carrier_IATA"=p_iata and f."Aircraft_Type_IATA"=tc and f."Aircraft_Series_Subtype"=st
        and upper(btrim(f."Carrier_Variant_Code"))=variant_code and upper(btrim(f."Aircraft_Registration"))=reg
    ) then raise exception 'Unknown registration for Series/Sub-Series' using errcode='23503'; end if;

    insert into "Basic_Carrier_Record"."Aircraft_Limiting_Weight_Values"
      ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Table_Name","Carrier_Variant_Code","Aircraft_Registration",
       "Zero_Fuel_Weight","Landing_Weight","Take_Off_Weight","Ramp_Taxi_Weight","Remarks")
    values(p_iata,tc,st,tn,variant_code,reg,z,l,t,r,rem);
  end loop;
  return "Basic_Carrier_Record".get_aircraft_f1(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_f1(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_f1_rows(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_f1(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_f1_rows(text,text,text,text,jsonb) to authenticated;

notify pgrst,'reload schema';
commit;
