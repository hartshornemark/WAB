begin;

create table if not exists "Basic_Carrier_Record"."Carrier_Aircraft_D4_Settings" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Doors_Active" boolean not null default false,
  "Locks_Active" boolean not null default false,
  "Missing_Restraints_Active" boolean not null default false,
  "Updated_At" timestamptz not null default now(),
  constraint "Carrier_Aircraft_D4_Settings_pkey"
    primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
  constraint "Carrier_Aircraft_D4_Settings_aircraft_fkey"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data"
      ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update cascade on delete cascade
);

alter table "Basic_Carrier_Record"."Carrier_Aircraft_D4_Settings" enable row level security;
revoke all on table "Basic_Carrier_Record"."Carrier_Aircraft_D4_Settings" from public,anon,authenticated;

-- Preserve the current behaviour for aircraft where D4 data has already been entered.
insert into "Basic_Carrier_Record"."Carrier_Aircraft_D4_Settings"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Doors_Active")
select distinct h."Carrier_IATA",h."Aircraft_Type_IATA",h."Aircraft_Series_Subtype",true
from "Basic_Carrier_Record"."Aircraft_Holds" h
where h."Hold_DOOR_Start" is not null
   or h."Hold_DOOR_End" is not null
   or h."Hold_DOOR_Height" is not null
   or h."Hold_DOOR_Orientation" is not null
on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update
set "Doors_Active"=true,"Updated_At"=now();

create or replace function "Basic_Carrier_Record".get_aircraft_d4(
  p_iata text,p_type_code text,p_subtype text
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  can_view boolean:=(select auth.uid()) is not null and
    (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
  can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  doors_active boolean:=false;
  locks_active boolean:=false;
  missing_active boolean:=false;
  door_rows jsonb;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(
    select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st
  ) then raise exception 'Aircraft not found' using errcode='23503'; end if;

  select s."Doors_Active",s."Locks_Active",s."Missing_Restraints_Active"
    into doors_active,locks_active,missing_active
  from "Basic_Carrier_Record"."Carrier_Aircraft_D4_Settings" s
  where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st;
  doors_active:=coalesce(doors_active,false);
  locks_active:=coalesce(locks_active,false);
  missing_active:=coalesce(missing_active,false);

  select coalesce(jsonb_agg(jsonb_build_object(
    'holdId',btrim(h."Hold_Name_ID"),
    'holdType',btrim(h."Hold_Type"),
    'deckName',coalesce(d."Deck_Display_Name",h."Hold_Deck_Location"),
    'forwardArm',h."Hold_DOOR_Start",
    'aftArm',h."Hold_DOOR_End",
    'height',h."Hold_DOOR_Height",
    'orientation',nullif(btrim(h."Hold_DOOR_Orientation"),'')
  ) order by
    case when upper(btrim(h."Hold_Type"))='ULD' then 0 else 1 end,
    h."Hold_BA_Centroid" asc nulls last,
    case when btrim(h."Hold_Name_ID") ~ '^[0-9]+$' then btrim(h."Hold_Name_ID")::integer end asc nulls last,
    btrim(h."Hold_Name_ID")
  ),'[]'::jsonb) into door_rows
  from "Basic_Carrier_Record"."Aircraft_Holds" h
  left join "Basic_Carrier_Record"."MASTER_Deck_Types" d on d."Deck_Code"=h."Hold_Deck_Location"
  where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st;

  return jsonb_build_object(
    'canView',can_view,'canEdit',can_edit,
    'revision',md5(jsonb_build_object(
      'doorsActive',doors_active,'locksActive',locks_active,
      'missingRestraintsActive',missing_active,'doors',door_rows
    )::text),
    'typeCode',tc,'subtype',st,
    'doorsActive',doors_active,'locksActive',locks_active,
    'missingRestraintsActive',missing_active,'doors',door_rows
  );
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_d4_applicability(
  p_iata text,p_type_code text,p_subtype text,p_revision text,p_section text,p_active boolean
) returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))
    then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st)->>'revision'<>p_revision
    then raise exception 'Conflict' using errcode='40001'; end if;
  if p_section<>'doors' then raise exception 'This D4 section is not supported yet' using errcode='23514'; end if;

  insert into "Basic_Carrier_Record"."Carrier_Aircraft_D4_Settings"
    ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Doors_Active","Updated_At")
  values(p_iata,tc,st,p_active,now())
  on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set
    "Doors_Active"=excluded."Doors_Active","Updated_At"=now();

  return "Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st);
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_d4(
  p_iata text,p_type_code text,p_subtype text,p_revision text,p_doors jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare tc text:=upper(btrim(p_type_code));st text:=upper(btrim(p_subtype));current_data jsonb;item jsonb;hold_id text;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))
    then raise exception 'Not authorised' using errcode='42501'; end if;
  current_data:="Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st);
  if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if not (current_data->>'doorsActive')::boolean then raise exception 'D4 Doors are optional and not selected' using errcode='23514'; end if;
  if jsonb_typeof(p_doors)<>'array' or jsonb_array_length(p_doors)<>(
    select count(*) from "Basic_Carrier_Record"."Aircraft_Holds"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st
  ) then raise exception 'Every hold requires one door' using errcode='22023'; end if;

  for item in select value from jsonb_array_elements(p_doors) loop
    hold_id:=upper(btrim(item->>'holdId'));
    update "Basic_Carrier_Record"."Aircraft_Holds" set
      "Hold_DOOR_Start"=(item->>'forwardArm')::double precision,
      "Hold_DOOR_End"=(item->>'aftArm')::double precision,
      "Hold_DOOR_Height"=(item->>'height')::double precision,
      "Hold_DOOR_Orientation"=upper(btrim(item->>'orientation'))
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc
      and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id;
    if not found then raise exception 'Unknown hold' using errcode='23503'; end if;
  end loop;
  return "Basic_Carrier_Record".get_aircraft_d4(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_d4(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d4(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_d4(text,text,text,text,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d4(text,text,text,text,jsonb) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_d4_applicability(text,text,text,text,text,boolean) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d4_applicability(text,text,text,text,text,boolean) to authenticated;

commit;
