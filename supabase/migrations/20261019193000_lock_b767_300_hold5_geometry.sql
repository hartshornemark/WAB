begin;

-- Hold 5 / aft loose-baggage geometry is physical B767-300 structure. Publish
-- it once in the aircraft layout and airframe libraries, then keep every
-- carrier D2/D4 record aligned to that common definition.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type,aircraft_subtype,version,bucket,object_path,sha256,byte_size,
   nose_arm_m,datum_description,datum_source,source_drawing,calibration)
select aircraft_type,aircraft_subtype,3,bucket,
       '763/300/bebefb2361addebf438518664d96213cbeaddff7f1f42257b2c427658f32b183.svg',
       'bebefb2361addebf438518664d96213cbeaddff7f1f42257b2c427658f32b183',144368,
       nose_arm_m,datum_description,
       'FAA Type Certificate Data Sheet A1NM Revision 40 datum; carrier-reviewed B767-300 Hold 5 limits and bulk-door geometry, 19 October 2026.',
       source_drawing,
       calibration || jsonb_build_object(
         'holdArmDefaults',coalesce(calibration->'holdArmDefaults','{}'::jsonb)
           || jsonb_build_object('ALB',jsonb_build_object('from',1556.2,'to',1666.2),'5',jsonb_build_object('from',1556.2,'to',1666.2)),
         'diagramCaption','Boeing 767-300 master outline, tail left and nose right. Station 0.0 is 92.5 inches forward of the airplane nose. Hold 5 is locked at STA 1556.2–1666.2; its 38-inch left cargo door is locked at STA 1592.2–1630.2.'
       )
from "Basic_Carrier_Record"."Aircraft_Layout_Versions"
where aircraft_type='763' and aircraft_subtype='300' and version=2
on conflict (aircraft_type,aircraft_subtype,version) do nothing;

insert into "Basic_Carrier_Record"."Aircraft_Layout_Active"
  (aircraft_type,aircraft_subtype,version_id)
select aircraft_type,aircraft_subtype,id
from "Basic_Carrier_Record"."Aircraft_Layout_Versions"
where aircraft_type='763' and aircraft_subtype='300' and version=3
on conflict (aircraft_type,aircraft_subtype) do update set
  version_id=excluded.version_id,activated_at=now(),activated_by=auth.uid();

insert into "Basic_Carrier_Record"."Airframe_Geometry_Versions"
  (family_code,version,source_layout_version_id,aircraft_length,nose_arm,arm_unit,source_description)
select 'BOEING_767_300',3,id,2163.0,92.5,'IN',
       'Locked B767-300 Hold 5 and bulk cargo-door geometry based on the reviewed carrier station data.'
from "Basic_Carrier_Record"."Aircraft_Layout_Versions"
where aircraft_type='763' and aircraft_subtype='300' and version=3
on conflict (family_code,version) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Profiles"
  (geometry_version_id,profile_code,profile_name,door_layout,passenger_cabin,main_deck_cargo,rear_centre_tank,notes)
select id,'STANDARD','Standard passenger','STANDARD',true,false,false,
       'Hold 5 and its left bulk cargo door are immutable B767-300 geometry.'
from "Basic_Carrier_Record"."Airframe_Geometry_Versions"
where family_code='BOEING_767_300' and version=3
on conflict (geometry_version_id,profile_code) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Decks"
  (geometry_version_id,profile_code,deck_code,deck_name,deck_purpose,display_order)
select geometry.id,'STANDARD',deck.code,deck.name,deck.purpose,deck.display_order
from "Basic_Carrier_Record"."Airframe_Geometry_Versions" geometry
cross join (values
  ('MAIN','Main Deck','PASSENGER',1::smallint),
  ('LOWER','Lower Deck','CARGO',2::smallint)
) as deck(code,name,purpose,display_order)
where geometry.family_code='BOEING_767_300' and geometry.version=3
on conflict (geometry_version_id,profile_code,deck_code) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Zones"
  (geometry_version_id,profile_code,deck_code,zone_kind,zone_code,zone_name,
   balance_arm_from,balance_arm_to,display_order,source_reference,locked)
select id,'STANDARD','LOWER','HOLD','5','Hold 5 / Aft Loose Baggage',
       1556.2,1666.2,3,
       'Carrier-reviewed B767-300 Hold 5: centroid STA 1611.2, limits STA 1556.2–1666.2.',true
from "Basic_Carrier_Record"."Airframe_Geometry_Versions"
where family_code='BOEING_767_300' and version=3
on conflict (geometry_version_id,profile_code,deck_code,zone_kind,zone_code) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Doors"
  (geometry_version_id,profile_code,deck_code,door_code,door_purpose,
   balance_arm_from,balance_arm_to,source_reference,locked)
select id,'STANDARD','LOWER','5','CARGO',1592.2,1630.2,
       'Carrier-reviewed B767-300 Hold 5 left door: centroid STA 1611.2, width 38 inches.',true
from "Basic_Carrier_Record"."Airframe_Geometry_Versions"
where family_code='BOEING_767_300' and version=3
on conflict (geometry_version_id,profile_code,deck_code,door_code) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Active"(family_code,version_id)
select family_code,id
from "Basic_Carrier_Record"."Airframe_Geometry_Versions"
where family_code='BOEING_767_300' and version=3
on conflict (family_code) do update set
  version_id=excluded.version_id,activated_at=now(),activated_by=auth.uid();

create or replace function "Basic_Carrier_Record".b767_300_hold5_arm(p_inches numeric,p_unit text)
returns numeric language sql immutable set search_path='' as $$
  select case upper(coalesce(btrim(p_unit),'IN'))
    when 'M' then p_inches*0.0254
    when 'CM' then p_inches*2.54
    when 'FT' then p_inches/12.0
    else p_inches
  end;
$$;

create or replace function "Basic_Carrier_Record".enforce_b767_300_hold5_geometry()
returns trigger language plpgsql set search_path='' as $$
declare length_unit text;
begin
  if new."Aircraft_Type_IATA"='763'
     and new."Aircraft_Series_Subtype"='300'
     and upper(coalesce(nullif(split_part(btrim(new."Hold_Name_ID"),':',2),''),btrim(new."Hold_Name_ID"))) in ('ALB','5') then
    select settings."Length_Unit" into length_unit
    from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" settings
    where settings."Carrier_IATA"=new."Carrier_IATA"
      and settings."Aircraft_Type_IATA"=new."Aircraft_Type_IATA"
      and settings."Aircraft_Series_Subtype"=new."Aircraft_Series_Subtype";
    length_unit:=coalesce(length_unit,'IN');
    new."Hold_BA_Start":="Basic_Carrier_Record".b767_300_hold5_arm(1556.2,length_unit);
    new."Hold_BA_Centroid":="Basic_Carrier_Record".b767_300_hold5_arm(1611.2,length_unit);
    new."Hold_BA_End":="Basic_Carrier_Record".b767_300_hold5_arm(1666.2,length_unit);
    new."Hold_DOOR_Start":="Basic_Carrier_Record".b767_300_hold5_arm(1592.2,length_unit);
    new."Hold_DOOR_End":="Basic_Carrier_Record".b767_300_hold5_arm(1630.2,length_unit);
    new."Hold_DOOR_Height":=1.1684;
    new."Hold_DOOR_Orientation":='L';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_b767_300_hold5_geometry
on "Basic_Carrier_Record"."Aircraft_Holds";
create trigger enforce_b767_300_hold5_geometry
before insert or update on "Basic_Carrier_Record"."Aircraft_Holds"
for each row execute function "Basic_Carrier_Record".enforce_b767_300_hold5_geometry();

-- Reconcile every current B767-300 sheet through the same trigger.
update "Basic_Carrier_Record"."Aircraft_Holds"
set "Hold_BA_Centroid"="Hold_BA_Centroid"
where "Aircraft_Type_IATA"='763' and "Aircraft_Series_Subtype"='300'
  and upper(coalesce(nullif(split_part(btrim("Hold_Name_ID"),':',2),''),btrim("Hold_Name_ID"))) in ('ALB','5');

revoke all on function "Basic_Carrier_Record".b767_300_hold5_arm(numeric,text) from public,anon;
grant execute on function "Basic_Carrier_Record".b767_300_hold5_arm(numeric,text) to authenticated;

commit;
