begin;

-- The Dash 8 AMM defines basic aircraft station X 00.00 as 43 inches
-- forward of the nose. The EASA TCDS separately locates the physical datum
-- reference plate at Station 423.0 on the underside of the fuselage.
update "Basic_Carrier_Record"."Aircraft_Layout_Versions" layout
set nose_arm_m=1.092200,
  datum_description='Aircraft station X 00.00 is 43 inches (1.0922 m) forward of the aircraft nose; station values increase aft.',
  datum_source='Dash 8 AMM Chapter 06, 06-20-00 Aircraft Stations. EASA TCDS EASA.IM.A.191 Issue 16 separately locates the datum reference plate at Station 423.0 inches on the fuselage centreline.',
  calibration=jsonb_set(
    jsonb_set(calibration,'{noseArm}','43'::jsonb,true),
    '{diagramCaption}',
    to_jsonb('Fuselage section traced from the Q300 Model 311 plan. X 00.00 is 43 inches forward of the nose; the Station 423 datum reference plate is a separate physical reference. Dashed aft join is indicative.'::text),
    true
  )
from "Basic_Carrier_Record"."Aircraft_Layout_Active" active
where active.version_id=layout.id
  and active.aircraft_type='DH3' and active.aircraft_subtype='300';

with source as (
  select v.id as layout_version_id
  from "Basic_Carrier_Record"."Aircraft_Layout_Active" a
  join "Basic_Carrier_Record"."Aircraft_Layout_Versions" v on v.id=a.version_id
  where a.aircraft_type='DH3' and a.aircraft_subtype='300'
), inserted_geometry as (
  insert into "Basic_Carrier_Record"."Airframe_Geometry_Versions"
    (family_code,version,source_layout_version_id,aircraft_length,nose_arm,arm_unit,source_description)
  select 'DE_HAVILLAND_DHC8_300',2,layout_version_id,800.000000,43.000000,'IN',
    'Q300 Model 311 station-based geometry. Dash 8 AMM Chapter 06 defines X 00.00 as 43 inches forward of the nose; EASA TCDS EASA.IM.A.191 locates the underside datum reference plate at Station 423.0 inches.'
  from source
  returning id
)
insert into "Basic_Carrier_Record"."Airframe_Geometry_Profiles"
  (geometry_version_id,profile_code,profile_name,door_layout,passenger_cabin,
   main_deck_cargo,rear_centre_tank,notes)
select id,'STANDARD','Standard passenger','STANDARD',true,false,false,
  'The station-calibrated fuselage and tapered aft-hold outline are reusable. X 00.00 is fixed 43 inches forward of the nose; Station 423 identifies the physical datum reference plate.'
from inserted_geometry;

update "Basic_Carrier_Record"."Airframe_Geometry_Active" active
set version_id=geometry.id,activated_at=now(),activated_by=auth.uid()
from "Basic_Carrier_Record"."Airframe_Geometry_Versions" geometry
where active.family_code='DE_HAVILLAND_DHC8_300'
  and geometry.family_code=active.family_code and geometry.version=2;

-- Extend the existing fixed-datum protection to the Dash 8-300 IATA identity.
create or replace function "Basic_Carrier_Record".fixed_aircraft_nose_arm(p_type text,p_unit text)
returns numeric language sql immutable set search_path='' as $$
 select case
   when upper(btrim(p_type)) in ('318','319','320','321','32A','32B','32N','32Q') then
     case upper(p_unit) when 'M' then 2.54 when 'CM' then 254 when 'IN' then 100 when 'FT' then round(100.0/12,6) end
   when upper(btrim(p_type))='DH3' then
     case upper(p_unit) when 'M' then 1.0922 when 'CM' then 109.22 when 'IN' then 43 when 'FT' then round(43.0/12,6) end
 end;
$$;

update "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
set "Balance_Arm_At_Nose"=1.092200
where "Aircraft_Type_IATA"='DH3';

update "Basic_Carrier_Record"."Carrier_Basic_Index_MAC" c
set "Balance_Arm_At_Nose"="Basic_Carrier_Record".fixed_aircraft_nose_arm(c."Aircraft_Type_IATA",u."Length_Unit")
from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" u
where c."Carrier_IATA"=u."Carrier_IATA"
  and c."Aircraft_Type_IATA"=u."Aircraft_Type_IATA"
  and c."Aircraft_Series_Subtype"=u."Aircraft_Series_Subtype"
  and c."Aircraft_Type_IATA"='DH3';

commit;
