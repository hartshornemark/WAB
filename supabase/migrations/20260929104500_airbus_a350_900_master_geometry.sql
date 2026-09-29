begin;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Families"
  (family_code,manufacturer,model)
values ('AIRBUS_A350_900','Airbus','A350-900');

with source as (
  select v.id
  from "Basic_Carrier_Record"."Aircraft_Layout_Active" a
  join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=a.version_id
  where a.aircraft_type='359' and a.aircraft_subtype='900'
), inserted as (
  insert into "Basic_Carrier_Record"."Airframe_Geometry_Versions"
    (family_code,version,source_layout_version_id,aircraft_length,nose_arm,arm_unit,source_description)
  select 'AIRBUS_A350_900',1,id,66.800000,1.840000,'M',
    'Airbus A350-900 plan-view geometry from the supplied Airbus drawing. Includes the confirmed 1.84 m datum, saved cargo-door alignment and approved tapered bulk-hold profile.'
  from source returning id
)
insert into "Basic_Carrier_Record"."Airframe_Geometry_Active"(family_code,version_id)
select 'AIRBUS_A350_900',id from inserted;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Profiles"
  (geometry_version_id,profile_code,profile_name,door_layout,passenger_cabin,main_deck_cargo,rear_centre_tank,notes)
select active.version_id,'STANDARD','Standard passenger','STANDARD',true,false,false,
  'The verified drawing calibration retains the forward-hold correction, aft-door compartment anchor and tapered Hold 5 profile.'
from "Basic_Carrier_Record"."Airframe_Geometry_Active" active
where active.family_code='AIRBUS_A350_900';

insert into "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
  (aircraft_type,aircraft_subtype,family_code,profile_code)
values ('359','900','AIRBUS_A350_900','STANDARD');

commit;
