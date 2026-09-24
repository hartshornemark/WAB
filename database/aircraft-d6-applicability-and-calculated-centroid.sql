begin;

create table if not exists "Basic_Carrier_Record"."Carrier_Aircraft_D6_Settings" (
  "Carrier_IATA" varchar(2) not null,
  "Aircraft_Type_IATA" varchar(3) not null,
  "Aircraft_Series_Subtype" varchar(4) not null,
  "Potable_Water_Applicable" boolean,
  "Galley_Other_Applicable" boolean,
  "Updated_At" timestamptz not null default now(),
  constraint "Carrier_Aircraft_D6_Settings_pkey"
    primary key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype"),
  constraint "Carrier_Aircraft_D6_Settings_aircraft_fkey"
    foreign key ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    references "Basic_Carrier_Record"."Basic_Aircraft_Data"
      ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype")
    on update cascade on delete cascade
);

alter table "Basic_Carrier_Record"."Carrier_Aircraft_D6_Settings" enable row level security;
revoke all on table "Basic_Carrier_Record"."Carrier_Aircraft_D6_Settings" from public,anon,authenticated;

insert into "Basic_Carrier_Record"."Carrier_Aircraft_D6_Settings"
  ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Potable_Water_Applicable","Galley_Other_Applicable")
select a."Carrier_IATA",a."Aircraft_Type_IATA",a."Aircraft_Series_Subtype",
  case when exists(
    select 1 from "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations" w
    where w."Carrier_IATA"=a."Carrier_IATA"
      and w."Aircraft_Type_IATA"=a."Aircraft_Type_IATA"
      and w."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype"
  ) then true end,
  case when exists(
    select 1 from "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations" g
    where g."Carrier_IATA"=a."Carrier_IATA"
      and g."Aircraft_Type_IATA"=a."Aircraft_Type_IATA"
      and g."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype"
  ) then true end
from "Basic_Carrier_Record"."Basic_Aircraft_Data" a
where exists(
    select 1 from "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations" w
    where w."Carrier_IATA"=a."Carrier_IATA"
      and w."Aircraft_Type_IATA"=a."Aircraft_Type_IATA"
      and w."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype"
  ) or exists(
    select 1 from "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations" g
    where g."Carrier_IATA"=a."Carrier_IATA"
      and g."Aircraft_Type_IATA"=a."Aircraft_Type_IATA"
      and g."Aircraft_Series_Subtype"=a."Aircraft_Series_Subtype"
  )
on conflict do nothing;

create or replace function "Basic_Carrier_Record".get_aircraft_d6(
  p_iata text,p_type_code text,p_subtype text
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  can_view boolean:=(select auth.uid()) is not null and
    (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW') or private.has_global_permission('AIRCRAFT_CONFIG_VIEW'));
  can_edit boolean:=private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT');
  water jsonb;
  galley jsonb;
  water_applicable boolean;
  galley_applicable boolean;
begin
  if not can_view then raise exception 'Not authorised' using errcode='42501'; end if;
  if not exists(
    select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st
  ) then raise exception 'Aircraft not found' using errcode='23503'; end if;

  select s."Potable_Water_Applicable",s."Galley_Other_Applicable"
    into water_applicable,galley_applicable
  from "Basic_Carrier_Record"."Carrier_Aircraft_D6_Settings" s
  where s."Carrier_IATA"=p_iata and s."Aircraft_Type_IATA"=tc and s."Aircraft_Series_Subtype"=st;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',btrim("PW_Tank_Short_Form"),'name',btrim("PW_Tank_Name"),
    'maxWeight',"PW_Tank_Max_Weight",'centroid',"PW_Tank_BA_Centroid",
    'index',"PW_Tnk_Index_Per_Weight_Unit"
  ) order by btrim("PW_Tank_Short_Form")),'[]') into water
  from "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations"
  where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',btrim("Location_Short_Form_ID"),'description',btrim("Location_Description"),
    'maxWeight',"Location_Max_Weight",'centroid',"Location_BA_Centroid",
    'index',"Location_Index_Per_Weight_Unit"
  ) order by btrim("Location_Short_Form_ID")),'[]') into galley
  from "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations"
  where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;

  return jsonb_build_object(
    'canView',can_view,'canEdit',can_edit,
    'revision',md5(jsonb_build_object(
      'waterApplicable',water_applicable,'galleyApplicable',galley_applicable,
      'waterLocations',water,'galleyLocations',galley
    )::text),
    'typeCode',tc,'subtype',st,
    'waterApplicable',water_applicable,'galleyApplicable',galley_applicable,
    'waterLocations',water,'galleyLocations',galley
  );
end $$;

create or replace function "Basic_Carrier_Record".save_aircraft_d6(
  p_iata text,p_type_code text,p_subtype text,p_revision text,
  p_section text,p_applicable boolean,p_rows jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  tc text:=upper(btrim(p_type_code));
  st text:=upper(btrim(p_subtype));
  item jsonb;
begin
  if not (private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_EDIT') or private.has_global_permission('AIRCRAFT_CONFIG_EDIT'))
    then raise exception 'Not authorised' using errcode='42501'; end if;
  if "Basic_Carrier_Record".get_aircraft_d6(p_iata,tc,st)->>'revision'<>p_revision
    then raise exception 'Conflict' using errcode='40001'; end if;
  if p_section not in ('waterLocations','galleyLocations') or p_applicable is null
    then raise exception 'Unknown D6 section' using errcode='22023'; end if;
  if jsonb_typeof(p_rows)<>'array'
    then raise exception 'Invalid D6 rows' using errcode='22023'; end if;

  insert into "Basic_Carrier_Record"."Carrier_Aircraft_D6_Settings"
    ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Potable_Water_Applicable","Galley_Other_Applicable","Updated_At")
  values(
    p_iata,tc,st,
    case when p_section='waterLocations' then p_applicable end,
    case when p_section='galleyLocations' then p_applicable end,
    now()
  )
  on conflict ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype") do update set
    "Potable_Water_Applicable"=case when p_section='waterLocations' then p_applicable else "Carrier_Aircraft_D6_Settings"."Potable_Water_Applicable" end,
    "Galley_Other_Applicable"=case when p_section='galleyLocations' then p_applicable else "Carrier_Aircraft_D6_Settings"."Galley_Other_Applicable" end,
    "Updated_At"=now();

  if not p_applicable or jsonb_array_length(p_rows)=0 then
    return "Basic_Carrier_Record".get_aircraft_d6(p_iata,tc,st);
  end if;

  if p_section='waterLocations' then
    for item in select value from jsonb_array_elements(p_rows) loop
      insert into "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations"
        ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","PW_Tank_Name","PW_Tank_Short_Form","PW_Tank_Max_Weight","PW_Tank_BA_Centroid","PW_Tnk_Index_Per_Weight_Unit")
      values(
        p_iata,tc,st,btrim(item->>'name'),upper(btrim(item->>'id')),
        (item->>'maxWeight')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision
      )
      on conflict ("Carrier_IATA","Aircraft_Type_IATA","PW_Tank_Short_Form","Aircraft_Series_Subtype") do update set
        "PW_Tank_Name"=excluded."PW_Tank_Name",
        "PW_Tank_Max_Weight"=excluded."PW_Tank_Max_Weight",
        "PW_Tank_BA_Centroid"=excluded."PW_Tank_BA_Centroid",
        "PW_Tnk_Index_Per_Weight_Unit"=excluded."PW_Tnk_Index_Per_Weight_Unit";
    end loop;
    delete from "Basic_Carrier_Record"."Aircraft_Potable_Water_Locations" w
    where w."Carrier_IATA"=p_iata and w."Aircraft_Type_IATA"=tc and w."Aircraft_Series_Subtype"=st
      and not exists(
        select 1 from jsonb_array_elements(p_rows) r
        where upper(btrim(r->>'id'))=btrim(w."PW_Tank_Short_Form")
      );
  else
    delete from "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=tc and "Aircraft_Series_Subtype"=st;
    for item in select value from jsonb_array_elements(p_rows) loop
      insert into "Basic_Carrier_Record"."Aircraft_Galley_and_Other_Locations"
        ("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Location_Description","Location_Short_Form_ID","Location_Max_Weight","Location_BA_Centroid","Location_Index_Per_Weight_Unit")
      values(
        p_iata,tc,st,btrim(item->>'description'),upper(btrim(item->>'id')),
        (item->>'maxWeight')::integer,(item->>'centroid')::double precision,(item->>'index')::double precision
      );
    end loop;
  end if;

  return "Basic_Carrier_Record".get_aircraft_d6(p_iata,tc,st);
end $$;

revoke all on function "Basic_Carrier_Record".get_aircraft_d6(text,text,text) from public,anon;
grant execute on function "Basic_Carrier_Record".get_aircraft_d6(text,text,text) to authenticated;
revoke all on function "Basic_Carrier_Record".save_aircraft_d6(text,text,text,text,text,boolean,jsonb) from public,anon;
grant execute on function "Basic_Carrier_Record".save_aircraft_d6(text,text,text,text,text,boolean,jsonb) to authenticated;

drop function if exists "Basic_Carrier_Record".save_aircraft_d6(text,text,text,text,text,jsonb);

commit;
