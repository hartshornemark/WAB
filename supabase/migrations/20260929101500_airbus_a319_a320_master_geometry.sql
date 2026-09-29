begin;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Families"
  (family_code,manufacturer,model)
values
  ('AIRBUS_A319','Airbus','A319'),
  ('AIRBUS_A320','Airbus','A320');

with sources as (
  select a.aircraft_type,a.aircraft_subtype,v.id as layout_version_id
  from "Basic_Carrier_Record"."Aircraft_Layout_Active" a
  join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=a.version_id
  where (a.aircraft_type,a.aircraft_subtype) in (('319','100'),('320','200'))
), inserted as (
  insert into "Basic_Carrier_Record"."Airframe_Geometry_Versions"
    (family_code,version,source_layout_version_id,aircraft_length,nose_arm,arm_unit,source_description)
  select case aircraft_type when '319' then 'AIRBUS_A319' else 'AIRBUS_A320' end,
    1,layout_version_id,
    case aircraft_type when '319' then 33.840000 else 37.570000 end,
    2.540000,'M',
    case aircraft_type
      when '319' then 'Airbus A319 plan-view geometry from the supplied Airbus drawing; fixed A320-family datum.'
      else 'Airbus A320 plan-view geometry from the supplied Airbus drawing; fixed A320-family datum. The legacy cargo plotting origin remains layout calibration only.'
    end
  from sources
  returning id,family_code
)
insert into "Basic_Carrier_Record"."Airframe_Geometry_Active"(family_code,version_id)
select family_code,id from inserted;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Profiles"
  (geometry_version_id,profile_code,profile_name,door_layout,passenger_cabin,main_deck_cargo,rear_centre_tank,notes)
select active.version_id,'STANDARD','Standard passenger','STANDARD',true,false,false,
  'Passenger, cargo-door and structural hold bounds require authoritative source values.'
from "Basic_Carrier_Record"."Airframe_Geometry_Active" active
where active.family_code in ('AIRBUS_A319','AIRBUS_A320');

insert into "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
  (aircraft_type,aircraft_subtype,family_code,profile_code)
values
  ('319','100','AIRBUS_A319','STANDARD'),
  ('320','100','AIRBUS_A320','STANDARD'),
  ('320','200','AIRBUS_A320','STANDARD');

commit;
