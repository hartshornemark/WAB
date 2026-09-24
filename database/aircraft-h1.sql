begin;

create table if not exists "Basic_Carrier_Record"."Carrier_Aircraft_H1_Settings" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "DGR_Exceptions_Active" boolean not null default false,
  "IATA_Exceptions_Active" boolean not null default false,
  "Special_Loads_Active" boolean not null default false,
  "Updated_At" timestamptz not null default now(),
  primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update cascade on delete cascade
);

create table if not exists "Basic_Carrier_Record"."Aircraft_Special_Load_Exceptions" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Exception_Type" varchar(16) not null,
  "Special_Load_Code" char(3) not null,
  "Incompatible_With" char(3) not null,
  "Remarks" varchar(500),
  primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Exception_Type","Special_Load_Code","Incompatible_With"),
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update cascade on delete cascade,
  foreign key ("Special_Load_Code") references "Basic_Carrier_Record"."MASTER_IATA_Special_Load_Codes"("Special_Load_Code") on update cascade,
  foreign key ("Incompatible_With") references "Basic_Carrier_Record"."MASTER_IATA_Special_Load_Codes"("Special_Load_Code") on update cascade,
  check ("Exception_Type" in ('DGR','IATA_SPECIAL')),
  check ("Special_Load_Code"<>"Incompatible_With"),
  check ("Remarks" is null or ("Remarks"=btrim("Remarks") and char_length("Remarks") between 1 and 500))
);

create table if not exists "Basic_Carrier_Record"."Aircraft_Special_Load_Limits" (
  "Row_ID" uuid primary key default gen_random_uuid(),
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Hold_Name_ID" char(3) not null,
  "Special_Load_Code" char(3) not null,
  "Location_Type" varchar(12),
  "Location_Reference" varchar(16),
  "Maximum_Quantity" integer not null,
  "Remarks" varchar(500),
  foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update cascade on delete cascade,
  foreign key ("Special_Load_Code") references "Basic_Carrier_Record"."MASTER_IATA_Special_Load_Codes"("Special_Load_Code") on update cascade,
  unique ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Hold_Name_ID","Special_Load_Code","Location_Type","Location_Reference"),
  check (("Location_Type" is null and "Location_Reference" is null) or ("Location_Type" in ('COMPARTMENT','POSITION') and "Location_Reference" is not null)),
  check ("Maximum_Quantity">=0),
  check ("Remarks" is null or ("Remarks"=btrim("Remarks") and char_length("Remarks") between 1 and 500))
);

create index if not exists "Aircraft_Special_Load_Limits_aircraft_idx" on "Basic_Carrier_Record"."Aircraft_Special_Load_Limits"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype");
alter table "Basic_Carrier_Record"."Carrier_Aircraft_H1_Settings" enable row level security;
alter table "Basic_Carrier_Record"."Aircraft_Special_Load_Exceptions" enable row level security;
alter table "Basic_Carrier_Record"."Aircraft_Special_Load_Limits" enable row level security;

create or replace function "Basic_Carrier_Record".get_aircraft_h1(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));can_view boolean;can_edit boolean;settings jsonb;dgr jsonb;iata_rows jsonb;limits jsonb;codes jsonb;holds jsonb;locations jsonb;uld boolean;
begin
  can_view:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW');
  can_edit:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" a where a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503'; end if;
  select to_jsonb(s) into settings from "Basic_Carrier_Record"."Carrier_Aircraft_H1_Settings" s where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st;
  select exists(select 1 from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st and btrim(h."Hold_Type")<>'BLK') into uld;
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(m."Special_Load_Code"),'description',btrim(m."Special_Load_Code_Description"),'prohibited',coalesce(a."Special_Load_Code_Is_Prohibited",false)) order by btrim(m."Special_Load_Code")),'[]') into codes
    from "Basic_Carrier_Record"."MASTER_IATA_Special_Load_Codes" m left join "Basic_Carrier_Record"."Carrier_Special_Load_Authorities" a on a."Carrier_IATA"=p_iata and a."Aircraft_Type_IATA"=tc and a."Aircraft_Series_Subtype"=st and a."Special_Load_Code"=m."Special_Load_Code";
  select coalesce(jsonb_agg(jsonb_build_object('id',btrim(h."Hold_Name_ID"),'name','Hold '||btrim(h."Hold_Name_ID"),'holdType',case when btrim(h."Hold_Type")='BLK' then 'BULK' else 'ULD' end) order by case when btrim(h."Hold_Type")='BLK' then 0 else 1 end,btrim(h."Hold_Name_ID")),'[]') into holds from "Basic_Carrier_Record"."Aircraft_Holds" h where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st;
  select coalesce(jsonb_agg(x.item order by x.sort_hold,x.sort_location),'[]') into locations from (
    select btrim(c."Hold_Name_ID") sort_hold,btrim(c."Compartment_ID") sort_location,jsonb_build_object('holdId',btrim(c."Hold_Name_ID"),'id',btrim(c."Compartment_ID"),'locationType','COMPARTMENT') item
      from "Basic_Carrier_Record"."Aircraft_Compartments" c join "Basic_Carrier_Record"."Aircraft_Holds" h on h."Carrier_IATA"=c."Carrier_IATA" and h."Aircraft_Type_IATA"=c."Aircraft_Type_IATA" and h."Aircraft_Series_Subtype"=c."Aircraft_Series_Subtype" and h."Hold_Name_ID"=c."Hold_Name_ID"
      where c."Carrier_IATA"=p_iata and c."Aircraft_Type_IATA"=tc and c."Aircraft_Series_Subtype"=st and btrim(h."Hold_Type")='BLK'
    union all
    select distinct btrim(p."Hold_Name_ID"),btrim(p."ULD_Position_ID"),jsonb_build_object('holdId',btrim(p."Hold_Name_ID"),'id',btrim(p."ULD_Position_ID"),'locationType','POSITION')
      from "Basic_Carrier_Record"."Carrier_ULD_Positions" p join "Basic_Carrier_Record"."Aircraft_Holds" h on h."Carrier_IATA"=p."Carrier_IATA" and h."Aircraft_Type_IATA"=p."Aircraft_Type_IATA" and h."Aircraft_Series_Subtype"=p."Aircraft_Series_Subtype" and h."Hold_Name_ID"=p."Hold_Name_ID"
      where p."Carrier_IATA"=p_iata and p."Aircraft_Type_IATA"=tc and p."Aircraft_Series_Subtype"=st and p."ULD_Row_Type"='POSITION' and btrim(h."Hold_Type")<>'BLK'
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(e."Special_Load_Code"),'incompatibleWith',btrim(e."Incompatible_With"),'remarks',e."Remarks") order by btrim(e."Special_Load_Code"),btrim(e."Incompatible_With")),'[]') into dgr from "Basic_Carrier_Record"."Aircraft_Special_Load_Exceptions" e where e."Carrier_IATA"=p_iata and e."Aircraft_Type_IATA"=tc and e."Aircraft_Series_Subtype"=st and e."Exception_Type"='DGR';
  select coalesce(jsonb_agg(jsonb_build_object('code',btrim(e."Special_Load_Code"),'incompatibleWith',btrim(e."Incompatible_With"),'remarks',e."Remarks") order by btrim(e."Special_Load_Code"),btrim(e."Incompatible_With")),'[]') into iata_rows from "Basic_Carrier_Record"."Aircraft_Special_Load_Exceptions" e where e."Carrier_IATA"=p_iata and e."Aircraft_Type_IATA"=tc and e."Aircraft_Series_Subtype"=st and e."Exception_Type"='IATA_SPECIAL';
  select coalesce(jsonb_agg(jsonb_build_object('holdId',btrim(l."Hold_Name_ID"),'code',btrim(l."Special_Load_Code"),'locationRef',l."Location_Reference",'maximumQuantity',l."Maximum_Quantity",'remarks',l."Remarks") order by btrim(l."Hold_Name_ID"),btrim(l."Special_Load_Code"),l."Location_Reference"),'[]') into limits from "Basic_Carrier_Record"."Aircraft_Special_Load_Limits" l where l."Carrier_IATA"=p_iata and l."Aircraft_Type_IATA"=tc and l."Aircraft_Series_Subtype"=st;
  return jsonb_build_object('canView',can_view,'canEdit',can_edit,'revision',md5(coalesce(settings::text,'null')||dgr::text||iata_rows::text||limits::text),'typeCode',tc,'subtype',st,'applicabilityReviewed',settings is not null,'dgrActive',coalesce((settings->>'DGR_Exceptions_Active')::boolean,false),'iataActive',coalesce((settings->>'IATA_Exceptions_Active')::boolean,false),'specialLoadsActive',coalesce((settings->>'Special_Loads_Active')::boolean,false),'isUldAircraft',uld,'dgrRows',dgr,'iataRows',iata_rows,'specialLoadRows',limits,'codeOptions',codes,'holdOptions',holds,'locationOptions',locations);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_h1_applicability(p_iata text,p_type_code text,p_subtype text,p_revision text,p_dgr_active boolean,p_iata_active boolean,p_special_loads_active boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_h1(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  insert into "Basic_Carrier_Record"."Carrier_Aircraft_H1_Settings" values(p_iata,tc,st,p_dgr_active,p_iata_active,p_special_loads_active,now()) on conflict("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set "DGR_Exceptions_Active"=excluded."DGR_Exceptions_Active","IATA_Exceptions_Active"=excluded."IATA_Exceptions_Active","Special_Loads_Active"=excluded."Special_Loads_Active","Updated_At"=now();
  return "Basic_Carrier_Record".get_aircraft_h1(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_h1_exceptions(p_iata text,p_type_code text,p_subtype text,p_revision text,p_kind text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));kind text:=upper(btrim(p_kind));item jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_h1(p_iata,tc,st)->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if kind not in ('DGR','IATA_SPECIAL') or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 then raise exception 'At least one row required' using errcode='22023'; end if;
  delete from "Basic_Carrier_Record"."Aircraft_Special_Load_Exceptions" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and "Exception_Type"=kind;
  for item in select value from jsonb_array_elements(p_rows) loop
    insert into "Basic_Carrier_Record"."Aircraft_Special_Load_Exceptions"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Exception_Type","Special_Load_Code","Incompatible_With","Remarks") values(p_iata,tc,st,kind,upper(btrim(item->>'code')),upper(btrim(item->>'incompatibleWith')),nullif(btrim(item->>'remarks'),''));
  end loop;
  return "Basic_Carrier_Record".get_aircraft_h1(p_iata,tc,st);
end $$;

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

revoke all on function "Basic_Carrier_Record".get_aircraft_h1(text,text,text) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_h1_applicability(text,text,text,text,boolean,boolean,boolean) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_h1_exceptions(text,text,text,text,text,jsonb) from public,anon;
revoke all on function "Basic_Carrier_Record".save_aircraft_h1_special_loads(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_h1(text,text,text) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_h1_applicability(text,text,text,text,boolean,boolean,boolean) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_h1_exceptions(text,text,text,text,text,jsonb) to authenticated;
grant execute on function "Basic_Carrier_Record".save_aircraft_h1_special_loads(text,text,text,text,jsonb) to authenticated;

commit;
