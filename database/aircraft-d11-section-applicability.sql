begin;

create table if not exists "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Combined_Load_Limits_Applicable" boolean not null default false,
  "Floor_Loading_Limits_Applicable" boolean not null default false,
  "Asymmetrical_Load_Limits_Applicable" boolean not null default false,
  "Updated_At" timestamptz not null default now(),
  constraint "Carrier_Aircraft_D11_Settings_pkey" primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
  constraint "Carrier_Aircraft_D11_Settings_aircraft_fkey" foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") references "Basic_Carrier_Record"."Basic_Aircraft_Data"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") on update cascade on delete cascade
);
alter table "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" enable row level security;
revoke all on table "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" from public,anon,authenticated;

insert into "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings"(
  "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",
  "Combined_Load_Limits_Applicable","Floor_Loading_Limits_Applicable","Asymmetrical_Load_Limits_Applicable","Updated_At"
)
select distinct "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",false,true,false,now()
from "Basic_Carrier_Record"."Aircraft_Holds"
where "Floor_Loading_Limit" is not null
on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set
  "Floor_Loading_Limits_Applicable"=true,
  "Updated_At"=now();

create or replace function "Basic_Carrier_Record".get_aircraft_d11(p_iata text,p_type_code text,p_subtype text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  can_view boolean:=(select auth.uid()) is not null and (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
  can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  combined_active boolean;
  floor_active boolean;
  asymmetrical_active boolean;
  rows jsonb;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Aircraft not found' using errcode='23503'; end if;
  select
    coalesce((select "Combined_Load_Limits_Applicable" from "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),false),
    coalesce((select "Floor_Loading_Limits_Applicable" from "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),false),
    coalesce((select "Asymmetrical_Load_Limits_Applicable" from "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st),false)
  into combined_active,floor_active,asymmetrical_active;
  select coalesce(jsonb_agg(jsonb_build_object('holdId',btrim(h."Hold_Name_ID"),'holdType',btrim(h."Hold_Type"),'deckName',coalesce(d."Deck_Display_Name",h."Hold_Deck_Location"),'floorLoadingLimit',h."Floor_Loading_Limit") order by btrim(h."Hold_Type"),btrim(h."Hold_Name_ID")),'[]'::jsonb) into rows
  from "Basic_Carrier_Record"."Aircraft_Holds" h left join "Basic_Carrier_Record"."MASTER_Deck_Types" d on d."Deck_Code"=h."Hold_Deck_Location"
  where h."Carrier_IATA"=p_iata and h."Aircraft_Type_IATA"=tc and h."Aircraft_Series_Subtype"=st;
  return jsonb_build_object(
    'canView',can_view,'canEdit',can_edit,
    'revision',md5((jsonb_build_array(combined_active,floor_active,asymmetrical_active)||rows)::text),
    'typeCode',tc,'subtype',st,
    'combinedActive',combined_active,'floorActive',floor_active,'asymmetricalActive',asymmetrical_active,
    'floorLimits',rows
  );
end $$;
revoke all on function "Basic_Carrier_Record".get_aircraft_d11(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d11(text,text,text) to authenticated;

drop function if exists "Basic_Carrier_Record".save_aircraft_d11(text,text,text,text,jsonb);
create or replace function "Basic_Carrier_Record".save_aircraft_d11(p_iata text,p_type_code text,p_subtype text,p_revision text,p_applicable boolean,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  current_data jsonb;
  item jsonb;
  hold_id text;
  limit_value double precision;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')) then raise exception 'Not authorised' using errcode='42501'; end if;
  current_data:="Basic_Carrier_Record".get_aircraft_d11(p_iata,tc,st);
  if current_data->>'revision'<>p_revision then raise exception 'Conflict' using errcode='40001'; end if;
  if p_applicable is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Invalid D11 selection' using errcode='22023'; end if;

  insert into "Basic_Carrier_Record"."Carrier_Aircraft_D11_Settings"(
    "Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype",
    "Combined_Load_Limits_Applicable","Floor_Loading_Limits_Applicable","Asymmetrical_Load_Limits_Applicable","Updated_At"
  ) values(p_iata,tc,st,false,p_applicable,false,now())
  on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set
    "Floor_Loading_Limits_Applicable"=excluded."Floor_Loading_Limits_Applicable",
    "Updated_At"=now();

  if not p_applicable or jsonb_array_length(p_rows)=0 then return "Basic_Carrier_Record".get_aircraft_d11(p_iata,tc,st); end if;
  if jsonb_array_length(p_rows)<>(select count(*) from "Basic_Carrier_Record"."Aircraft_Holds" where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st) then raise exception 'Every hold requires a floor loading limit' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(p_rows) loop
    hold_id:=upper(btrim(item->>'holdId'));
    limit_value:=(item->>'floorLoadingLimit')::double precision;
    if limit_value<=0 then raise exception 'Invalid floor loading limit' using errcode='23514'; end if;
    update "Basic_Carrier_Record"."Aircraft_Holds" set "Floor_Loading_Limit"=limit_value where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st and btrim("Hold_Name_ID")=hold_id;
    if not found then raise exception 'Unknown hold' using errcode='23503'; end if;
  end loop;
  return "Basic_Carrier_Record".get_aircraft_d11(p_iata,tc,st);
end $$;
revoke all on function "Basic_Carrier_Record".save_aircraft_d11(text,text,text,text,boolean,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d11(text,text,text,text,boolean,jsonb) to authenticated;

commit;
