begin;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Families"
  (family_code,manufacturer,model)
values
  ('BOEING_737_800','Boeing','737-800'),
  ('BOEING_737_MAX9','Boeing','737 MAX 9');

with sources as (
  select a.aircraft_type,a.aircraft_subtype,v.id as layout_version_id
  from "Basic_Carrier_Record"."Aircraft_Layout_Active" a
  join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=a.version_id
  where (a.aircraft_type,a.aircraft_subtype) in (('738','800'),('7M9','900'))
), inserted as (
  insert into "Basic_Carrier_Record"."Airframe_Geometry_Versions"
    (family_code,version,source_layout_version_id,aircraft_length,nose_arm,arm_unit,source_description)
  select case aircraft_type when '738' then 'BOEING_737_800' else 'BOEING_737_MAX9' end,
    1,layout_version_id,
    case aircraft_type when '738' then 1554.000000 else 1659.919100 end,
    130.000000,'IN',
    case aircraft_type
      when '738' then 'Boeing 737-800 plan-view geometry from the supplied DXF; 130-inch datum from Boeing 737 AMM Task 06-21-00.'
      else 'Boeing 737 MAX 9 airport-planning plan-view geometry; 130-inch datum from Boeing 737 AMM Task 06-21-00.'
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
where active.family_code in ('BOEING_737_800','BOEING_737_MAX9');

insert into "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
  (aircraft_type,aircraft_subtype,family_code,profile_code)
values
  ('738','800','BOEING_737_800','STANDARD'),
  ('7M9','900','BOEING_737_MAX9','STANDARD');

commit;
