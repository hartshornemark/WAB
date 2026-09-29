begin;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Families"
  (family_code,manufacturer,model)
values ('DE_HAVILLAND_DHC8_300','De Havilland Canada','DHC-8-300 Dash 8');

with source as (
  select v.id
  from "Basic_Carrier_Record"."Aircraft_Layout_Active" a
  join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=a.version_id
  where a.aircraft_type='DH3' and a.aircraft_subtype='300'
), inserted as (
  insert into "Basic_Carrier_Record"."Airframe_Geometry_Versions"
    (family_code,version,source_layout_version_id,aircraft_length,nose_arm,arm_unit,source_description)
  select 'DE_HAVILLAND_DHC8_300',1,id,800.000000,0.000000,'IN',
    'Q300 Model 311 station-based geometry from Figures 2-5 and 2-8. Station anchors and the tapered aft-hold profile are authoritative for this overlay; the physical nose datum remains unverified.'
  from source returning id
)
insert into "Basic_Carrier_Record"."Airframe_Geometry_Active"(family_code,version_id)
select 'DE_HAVILLAND_DHC8_300',id from inserted;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Profiles"
  (geometry_version_id,profile_code,profile_name,door_layout,passenger_cabin,main_deck_cargo,rear_centre_tank,notes)
select active.version_id,'STANDARD','Standard passenger','STANDARD',true,false,false,
  'The station-calibrated fuselage and tapered aft-hold outline are reusable. Zero is retained only as the existing unverified master datum.'
from "Basic_Carrier_Record"."Airframe_Geometry_Active" active
where active.family_code='DE_HAVILLAND_DHC8_300';

insert into "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
  (aircraft_type,aircraft_subtype,family_code,profile_code)
values ('DH3','300','DE_HAVILLAND_DHC8_300','STANDARD');

commit;
