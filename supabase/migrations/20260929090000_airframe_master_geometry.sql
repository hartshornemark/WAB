begin;

-- An airframe family is the physical shell shared by operational aircraft
-- identities. Geometry is immutable and versioned; assignments select a
-- profile within the active family version.
create table "Basic_Carrier_Record"."Airframe_Geometry_Families" (
  family_code text primary key check (family_code ~ '^[A-Z0-9_]{2,24}$'),
  manufacturer text not null,
  model text not null,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

create table "Basic_Carrier_Record"."Airframe_Geometry_Versions" (
  id uuid primary key default gen_random_uuid(),
  family_code text not null references "Basic_Carrier_Record"."Airframe_Geometry_Families"(family_code),
  version integer not null check (version > 0),
  source_layout_version_id uuid not null references "Basic_Carrier_Record"."Aircraft_Layout_Versions"(id),
  aircraft_length numeric(14,6) not null check (aircraft_length > 0),
  nose_arm numeric(14,6) not null,
  arm_unit text not null check (arm_unit in ('M','IN')),
  source_description text not null,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  unique (family_code, version),
  unique (id, family_code)
);

create table "Basic_Carrier_Record"."Airframe_Geometry_Active" (
  family_code text primary key references "Basic_Carrier_Record"."Airframe_Geometry_Families"(family_code),
  version_id uuid not null,
  activated_at timestamptz not null default now(),
  activated_by uuid default auth.uid(),
  foreign key (version_id, family_code)
    references "Basic_Carrier_Record"."Airframe_Geometry_Versions"(id, family_code)
);

create table "Basic_Carrier_Record"."Airframe_Geometry_Profiles" (
  geometry_version_id uuid not null references "Basic_Carrier_Record"."Airframe_Geometry_Versions"(id),
  profile_code text not null check (profile_code ~ '^[A-Z0-9_]{2,24}$'),
  profile_name text not null,
  door_layout text not null,
  passenger_cabin boolean not null,
  main_deck_cargo boolean not null,
  rear_centre_tank boolean not null default false,
  notes text not null default '',
  primary key (geometry_version_id, profile_code)
);

create table "Basic_Carrier_Record"."Airframe_Geometry_Decks" (
  geometry_version_id uuid not null,
  profile_code text not null,
  deck_code text not null check (deck_code ~ '^[A-Z0-9_]{2,16}$'),
  deck_name text not null,
  deck_purpose text not null check (deck_purpose in ('PASSENGER','CARGO','MIXED')),
  display_order smallint not null check (display_order > 0),
  primary key (geometry_version_id, profile_code, deck_code),
  foreign key (geometry_version_id, profile_code)
    references "Basic_Carrier_Record"."Airframe_Geometry_Profiles"(geometry_version_id, profile_code)
);

create table "Basic_Carrier_Record"."Airframe_Geometry_Zones" (
  id uuid primary key default gen_random_uuid(),
  geometry_version_id uuid not null,
  profile_code text not null,
  deck_code text not null,
  zone_kind text not null check (zone_kind in ('CABIN','HOLD')),
  zone_code text not null,
  zone_name text not null,
  balance_arm_from numeric(14,6),
  balance_arm_to numeric(14,6),
  display_order smallint not null check (display_order > 0),
  source_reference text not null,
  locked boolean not null default true,
  foreign key (geometry_version_id, profile_code, deck_code)
    references "Basic_Carrier_Record"."Airframe_Geometry_Decks"(geometry_version_id, profile_code, deck_code),
  unique (geometry_version_id, profile_code, deck_code, zone_kind, zone_code),
  check ((balance_arm_from is null and balance_arm_to is null)
    or (balance_arm_from is not null and balance_arm_to is not null and balance_arm_from < balance_arm_to))
);

create table "Basic_Carrier_Record"."Airframe_Geometry_Doors" (
  id uuid primary key default gen_random_uuid(),
  geometry_version_id uuid not null,
  profile_code text not null,
  deck_code text not null,
  door_code text not null,
  door_purpose text not null check (door_purpose in ('PASSENGER','SERVICE','CARGO','EMERGENCY')),
  balance_arm_from numeric(14,6) not null,
  balance_arm_to numeric(14,6) not null,
  source_reference text not null,
  locked boolean not null default true,
  foreign key (geometry_version_id, profile_code, deck_code)
    references "Basic_Carrier_Record"."Airframe_Geometry_Decks"(geometry_version_id, profile_code, deck_code),
  unique (geometry_version_id, profile_code, deck_code, door_code),
  check (balance_arm_from < balance_arm_to)
);

create table "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments" (
  aircraft_type text not null,
  aircraft_subtype text not null,
  family_code text not null references "Basic_Carrier_Record"."Airframe_Geometry_Families"(family_code),
  profile_code text not null check (profile_code ~ '^[A-Z0-9_]{2,24}$'),
  assigned_at timestamptz not null default now(),
  assigned_by uuid default auth.uid(),
  primary key (aircraft_type, aircraft_subtype),
  foreign key (aircraft_type, aircraft_subtype)
    references "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"("Aircraft_Type_IATA", "Aircraft_Series_Subtype")
);

comment on table "Basic_Carrier_Record"."Airframe_Geometry_Families" is
  'Physical airframe families shared by multiple aircraft identities, engines and operational variants.';
comment on table "Basic_Carrier_Record"."Airframe_Geometry_Zones" is
  'Authoritative structural cabin and hold bounds only. Carrier limits, compartments, rows and loading arrangements remain carrier data.';
comment on table "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments" is
  'Explicit aircraft identity to active airframe-family profile mapping. Profiles are never inferred from a subtype name.';

alter table "Basic_Carrier_Record"."Airframe_Geometry_Families" enable row level security;
alter table "Basic_Carrier_Record"."Airframe_Geometry_Versions" enable row level security;
alter table "Basic_Carrier_Record"."Airframe_Geometry_Active" enable row level security;
alter table "Basic_Carrier_Record"."Airframe_Geometry_Profiles" enable row level security;
alter table "Basic_Carrier_Record"."Airframe_Geometry_Decks" enable row level security;
alter table "Basic_Carrier_Record"."Airframe_Geometry_Zones" enable row level security;
alter table "Basic_Carrier_Record"."Airframe_Geometry_Doors" enable row level security;
alter table "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments" enable row level security;

revoke all on
  "Basic_Carrier_Record"."Airframe_Geometry_Families",
  "Basic_Carrier_Record"."Airframe_Geometry_Versions",
  "Basic_Carrier_Record"."Airframe_Geometry_Active",
  "Basic_Carrier_Record"."Airframe_Geometry_Profiles",
  "Basic_Carrier_Record"."Airframe_Geometry_Decks",
  "Basic_Carrier_Record"."Airframe_Geometry_Zones",
  "Basic_Carrier_Record"."Airframe_Geometry_Doors",
  "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
from anon, authenticated;

create function "Basic_Carrier_Record".assign_airframe_geometry(
  p_type text, p_subtype text, p_family_code text, p_profile_code text
) returns void language plpgsql security definer set search_path='' as $$
declare active_version uuid;
begin
  if auth.uid() is null or not private.has_global_permission('AIRCRAFT_CONFIG_EDIT') then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  if not exists (
    select 1 from "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
    where "Aircraft_Type_IATA"=p_type and "Aircraft_Series_Subtype"=p_subtype
  ) then raise exception 'Aircraft identity not found' using errcode='23503'; end if;
  select a.version_id into active_version
  from "Basic_Carrier_Record"."Airframe_Geometry_Active" a
  where a.family_code=upper(btrim(p_family_code));
  if active_version is null or not exists (
    select 1 from "Basic_Carrier_Record"."Airframe_Geometry_Profiles" p
    where p.geometry_version_id=active_version and p.profile_code=upper(btrim(p_profile_code))
  ) then raise exception 'Active airframe geometry profile not found' using errcode='23503'; end if;
  insert into "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
    (aircraft_type, aircraft_subtype, family_code, profile_code)
  values (p_type, p_subtype, upper(btrim(p_family_code)), upper(btrim(p_profile_code)))
  on conflict (aircraft_type, aircraft_subtype) do update set
    family_code=excluded.family_code, profile_code=excluded.profile_code,
    assigned_at=now(), assigned_by=auth.uid();
end $$;

create function "Basic_Carrier_Record".activate_airframe_geometry(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare selected "Basic_Carrier_Record"."Airframe_Geometry_Versions";
begin
  if auth.uid() is null or not private.has_global_permission('AIRCRAFT_CONFIG_EDIT') then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  select * into strict selected from "Basic_Carrier_Record"."Airframe_Geometry_Versions" where id=p_id;
  if exists (
    select 1 from "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments" a
    where a.family_code=selected.family_code and not exists (
      select 1 from "Basic_Carrier_Record"."Airframe_Geometry_Profiles" p
      where p.geometry_version_id=selected.id and p.profile_code=a.profile_code
    )
  ) then raise exception 'The new version does not contain every assigned geometry profile'; end if;
  insert into "Basic_Carrier_Record"."Airframe_Geometry_Active"(family_code,version_id)
  values(selected.family_code,selected.id)
  on conflict(family_code) do update set version_id=excluded.version_id,
    activated_at=now(),activated_by=auth.uid();
end $$;

create function "Basic_Carrier_Record".get_aircraft_master_geometry(
  p_iata text, p_type text, p_subtype text
) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not (
    private.has_global_permission('AIRCRAFT_CONFIG_VIEW')
    or private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW')
  ) then raise exception 'Access denied' using errcode='42501'; end if;
  if not exists (
    select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type
      and "Aircraft_Series_Subtype"=p_subtype
  ) then raise exception 'Aircraft not available'; end if;
  return (
    select jsonb_build_object(
      'familyCode',f.family_code,'manufacturer',f.manufacturer,'model',f.model,
      'version',v.version,'aircraftLength',v.aircraft_length,'noseArm',v.nose_arm,
      'armUnit',v.arm_unit,'sourceDescription',v.source_description,
      'profileCode',p.profile_code,'profileName',p.profile_name,
      'doorLayout',p.door_layout,'passengerCabin',p.passenger_cabin,
      'mainDeckCargo',p.main_deck_cargo,'rearCentreTank',p.rear_centre_tank,
      'decks',coalesce((select jsonb_agg(jsonb_build_object(
        'code',d.deck_code,'name',d.deck_name,'purpose',d.deck_purpose,
        'displayOrder',d.display_order) order by d.display_order)
        from "Basic_Carrier_Record"."Airframe_Geometry_Decks" d
        where d.geometry_version_id=v.id and d.profile_code=p.profile_code),'[]'::jsonb),
      'zones',coalesce((select jsonb_agg(jsonb_build_object(
        'kind',z.zone_kind,'code',z.zone_code,'name',z.zone_name,'deckCode',z.deck_code,
        'balanceFrom',z.balance_arm_from,'balanceTo',z.balance_arm_to,
        'displayOrder',z.display_order,'sourceReference',z.source_reference,'locked',z.locked)
        order by z.display_order,z.zone_code)
        from "Basic_Carrier_Record"."Airframe_Geometry_Zones" z
        where z.geometry_version_id=v.id and z.profile_code=p.profile_code),'[]'::jsonb),
      'doors',coalesce((select jsonb_agg(jsonb_build_object(
        'code',d.door_code,'purpose',d.door_purpose,'deckCode',d.deck_code,
        'balanceFrom',d.balance_arm_from,'balanceTo',d.balance_arm_to,
        'sourceReference',d.source_reference,'locked',d.locked)
        order by d.balance_arm_from,d.door_code)
        from "Basic_Carrier_Record"."Airframe_Geometry_Doors" d
        where d.geometry_version_id=v.id and d.profile_code=p.profile_code),'[]'::jsonb)
    )
    from "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments" a
    join "Basic_Carrier_Record"."Airframe_Geometry_Families" f on f.family_code=a.family_code
    join "Basic_Carrier_Record"."Airframe_Geometry_Active" active on active.family_code=a.family_code
    join "Basic_Carrier_Record"."Airframe_Geometry_Versions" v on v.id=active.version_id
    join "Basic_Carrier_Record"."Airframe_Geometry_Profiles" p
      on p.geometry_version_id=v.id and p.profile_code=a.profile_code
    where a.aircraft_type=p_type and a.aircraft_subtype=p_subtype
  );
end $$;

-- Existing exact layout versions continue to win. An assigned airframe profile
-- supplies the shared immutable SVG only when that aircraft identity has no
-- dedicated published layout.
create or replace function "Basic_Carrier_Record".get_aircraft_layout(
  p_iata text,p_type text,p_subtype text
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null or not (
    private.has_global_permission('AIRCRAFT_CONFIG_VIEW')
    or private.has_carrier_permission(p_iata,'AIRCRAFT_CONFIG_VIEW')
  ) then raise exception 'Access denied' using errcode='42501'; end if;
  if not exists (
    select 1 from "Basic_Carrier_Record"."Basic_Aircraft_Data"
    where "Carrier_IATA"=p_iata and "Aircraft_Type_IATA"=p_type
      and "Aircraft_Series_Subtype"=p_subtype
  ) then raise exception 'Aircraft not available'; end if;
  select to_jsonb(v) into result
  from "Basic_Carrier_Record"."Aircraft_Layout_Active" a
  join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=a.version_id
  where a.aircraft_type=p_type and a.aircraft_subtype=p_subtype;
  if result is not null then return result; end if;
  return (
    select to_jsonb(layout_version) || jsonb_build_object(
      'aircraft_type',p_type,'aircraft_subtype',p_subtype,
      'asset_aircraft_type',layout_version.aircraft_type,
      'asset_aircraft_subtype',layout_version.aircraft_subtype,
      'geometry_family_code',assignment.family_code,
      'geometry_profile_code',assignment.profile_code,
      'calibration',layout_version.calibration || jsonb_build_object(
        'typeCode',p_type,'subtype',p_subtype,
        'diagramCaption','Shared '||family.model||' '||profile.profile_name||' airframe outline. '
          ||layout_version.calibration->>'diagramCaption'
      )
    )
    from "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments" assignment
    join "Basic_Carrier_Record"."Airframe_Geometry_Families" family
      on family.family_code=assignment.family_code
    join "Basic_Carrier_Record"."Airframe_Geometry_Active" active
      on active.family_code=assignment.family_code
    join "Basic_Carrier_Record"."Airframe_Geometry_Versions" geometry_version
      on geometry_version.id=active.version_id
    join "Basic_Carrier_Record"."Airframe_Geometry_Profiles" profile
      on profile.geometry_version_id=geometry_version.id
      and profile.profile_code=assignment.profile_code
    join "Basic_Carrier_Record"."Aircraft_Layout_Versions" layout_version
      on layout_version.id=geometry_version.source_layout_version_id
    where assignment.aircraft_type=p_type and assignment.aircraft_subtype=p_subtype
  );
end $$;

revoke all on function
  "Basic_Carrier_Record".assign_airframe_geometry(text,text,text,text),
  "Basic_Carrier_Record".activate_airframe_geometry(uuid),
  "Basic_Carrier_Record".get_aircraft_master_geometry(text,text,text)
from public,anon;
grant execute on function
  "Basic_Carrier_Record".assign_airframe_geometry(text,text,text,text),
  "Basic_Carrier_Record".activate_airframe_geometry(uuid),
  "Basic_Carrier_Record".get_aircraft_master_geometry(text,text,text)
to authenticated;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Families"
  (family_code,manufacturer,model)
values ('AIRBUS_A321','Airbus','A321');

with source as (
  select v.id
  from "Basic_Carrier_Record"."Aircraft_Layout_Active" a
  join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=a.version_id
  where a.aircraft_type='321' and a.aircraft_subtype='P2F'
), inserted as (
  insert into "Basic_Carrier_Record"."Airframe_Geometry_Versions"
    (family_code,version,source_layout_version_id,aircraft_length,nose_arm,arm_unit,source_description)
  select 'AIRBUS_A321',1,id,44.629301,2.540000,'M',
    'Airbus A321 plan-view geometry from the supplied 2013 ASCII DXF; fixed A320-family datum.'
  from source returning id
)
insert into "Basic_Carrier_Record"."Airframe_Geometry_Active"(family_code,version_id)
select 'AIRBUS_A321',id from inserted;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Profiles"
  (geometry_version_id,profile_code,profile_name,door_layout,passenger_cabin,main_deck_cargo,rear_centre_tank,notes)
select active.version_id,profile_code,profile_name,door_layout,passenger_cabin,main_deck_cargo,rear_centre_tank,notes
from "Basic_Carrier_Record"."Airframe_Geometry_Active" active
cross join (values
  ('STANDARD','Standard passenger','STANDARD',true,false,false,'Passenger doors and structural hold bounds require authoritative source values.'),
  ('ACF','Airbus Cabin Flex passenger','ACF',true,false,false,'ACF emergency-exit geometry must be recorded separately from the standard door layout.'),
  ('P2F','Passenger-to-freighter conversion','CONVERSION_SPECIFIC',false,true,false,'Conversion-specific main-deck cargo-door geometry is not established by the source drawing.'),
  ('XLR','A321XLR passenger','ACF_XLR',true,false,true,'Rear-centre-tank effects require XLR-specific lower-fuselage geometry.')
) as profiles(profile_code,profile_name,door_layout,passenger_cabin,main_deck_cargo,rear_centre_tank,notes)
where active.family_code='AIRBUS_A321';

insert into "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
  (aircraft_type,aircraft_subtype,family_code,profile_code)
values ('321','P2F','AIRBUS_A321','P2F');

commit;
