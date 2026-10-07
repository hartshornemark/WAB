begin;

-- Version 1 mirrored the source DXF, putting the aircraft outline in the
-- opposite direction to the application's tail-left / nose-right station
-- axis. Version 2 preserves the verified 92.5-inch datum and uses two
-- operational cargo anchors from the PE station schedule:
--   * FWD door forward edge = aft edge of 11P (STA 361.0)
--   * AFT door aft edge     = aft edge of 42  (STA 1470.2)
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type,aircraft_subtype,version,bucket,object_path,sha256,byte_size,
   nose_arm_m,datum_description,datum_source,source_drawing,calibration)
values
  ('763','300',2,'aircraft-layouts',
   '763/300/bd59b18b65adb3891364e680158e11b027e319a7c9a9b59815edfbb06fe97db0.svg',
   'bd59b18b65adb3891364e680158e11b027e319a7c9a9b59815edfbb06fe97db0',144311,
   2.349500,
   'Station 0.0 is 92.5 inches (2.3495 m) forward of the airplane nose; body stations increase aft.',
   'FAA Type Certificate Data Sheet A1NM, Revision 40, Boeing 767 datum statement.',
   'User-supplied Boeing 767-300 DXF; original plan-view vector geometry isolated and oriented tail-left/nose-right. Cargo-door anchors reviewed against the PE ULD station schedule.',
   '{"typeCode":"763","subtype":"300","length":2163,"noseArm":92.5,"armUnit":"IN","stationOriginX":1939.213513,"tailX":2213.077214,"span":2053.154428,"centreY":0,"imageFrame":{"x":92,"y":-150,"width":2189,"height":300},"cropLeft":92,"cropRight":2281,"holdY":-55,"holdHeight":110,"leftDoorY":-62,"rightDoorY":62,"labelCharWidth":0.58,"diagramCaption":"Boeing 767-300 master outline, tail left and nose right. Station 0.0 is 92.5 inches forward of the airplane nose. The station scale is anchored to the forward cargo-door start at the end of 11P and the aft cargo-door end at the end of bay 42; the forward opening lies across bays 12/13."}'::jsonb)
on conflict (aircraft_type,aircraft_subtype,version) do nothing;

insert into "Basic_Carrier_Record"."Aircraft_Layout_Active"
  (aircraft_type,aircraft_subtype,version_id)
select aircraft_type,aircraft_subtype,id
from "Basic_Carrier_Record"."Aircraft_Layout_Versions"
where aircraft_type='763' and aircraft_subtype='300' and version=2
on conflict (aircraft_type,aircraft_subtype) do update set
  version_id=excluded.version_id,
  activated_at=now(),
  activated_by=auth.uid();

insert into "Basic_Carrier_Record"."Airframe_Geometry_Versions"
  (family_code,version,source_layout_version_id,aircraft_length,nose_arm,arm_unit,source_description)
select 'BOEING_767_300',2,id,2163.000000,92.500000,'IN',
  'Corrected Boeing 767-300 tail-left/nose-right geometry. Cargo station scale is anchored to the PE forward and aft cargo-door/ULD boundaries.'
from "Basic_Carrier_Record"."Aircraft_Layout_Versions"
where aircraft_type='763' and aircraft_subtype='300' and version=2
on conflict (family_code,version) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Profiles"
  (geometry_version_id,profile_code,profile_name,door_layout,passenger_cabin,main_deck_cargo,rear_centre_tank,notes)
select geometry.id,'STANDARD','Standard passenger','STANDARD',true,false,false,
  'Baseline passenger airframe using the reviewed cargo-door/ULD station calibration.'
from "Basic_Carrier_Record"."Airframe_Geometry_Versions" geometry
where geometry.family_code='BOEING_767_300' and geometry.version=2
on conflict (geometry_version_id,profile_code) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Decks"
  (geometry_version_id,profile_code,deck_code,deck_name,deck_purpose,display_order)
select geometry.id,'STANDARD',deck.code,deck.name,deck.purpose,deck.display_order
from "Basic_Carrier_Record"."Airframe_Geometry_Versions" geometry
cross join (values
  ('MAIN','Main Deck','PASSENGER',1::smallint),
  ('LOWER','Lower Deck','CARGO',2::smallint)
) as deck(code,name,purpose,display_order)
where geometry.family_code='BOEING_767_300' and geometry.version=2
on conflict (geometry_version_id,profile_code,deck_code) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Active"(family_code,version_id)
select family_code,id
from "Basic_Carrier_Record"."Airframe_Geometry_Versions"
where family_code='BOEING_767_300' and version=2
on conflict (family_code) do update set
  version_id=excluded.version_id,
  activated_at=now(),
  activated_by=auth.uid();

commit;
