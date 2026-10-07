begin;

-- FAA TCDS A1NM Revision 40 fixes the 767 datum at Body Station 0.0,
-- 92.5 inches forward of the airplane nose. Keep it out of ordinary C4 edits.
create or replace function "Basic_Carrier_Record".fixed_aircraft_nose_arm(p_type text,p_unit text)
returns numeric language sql immutable set search_path='' as $$
 select case
   when upper(btrim(p_type)) in ('318','319','320','321','32A','32B','32N','32Q') then
     case upper(p_unit) when 'M' then 2.54 when 'CM' then 254 when 'IN' then 100 when 'FT' then round(100.0/12,6) end
   when upper(btrim(p_type))='DH3' then
     case upper(p_unit) when 'M' then 1.0922 when 'CM' then 109.22 when 'IN' then 43 when 'FT' then round(43.0/12,6) end
   when upper(btrim(p_type))='763' then
     case upper(p_unit) when 'M' then 2.3495 when 'CM' then 234.95 when 'IN' then 92.5 when 'FT' then round(92.5/12,6) end
 end;
$$;

update "Basic_Carrier_Record"."MASTER_Aircraft_Type_IATA"
set "Balance_Arm_At_Nose"=2.349500
where "Aircraft_Type_IATA"='763' and "Aircraft_Series_Subtype"='300';

update "Basic_Carrier_Record"."Carrier_Basic_Index_MAC" c
set "Balance_Arm_At_Nose"="Basic_Carrier_Record".fixed_aircraft_nose_arm(c."Aircraft_Type_IATA",u."Length_Unit")
from "Basic_Carrier_Record"."Carrier_Aircraft_C1_Settings" u
where c."Carrier_IATA"=u."Carrier_IATA"
  and c."Aircraft_Type_IATA"=u."Aircraft_Type_IATA"
  and c."Aircraft_Series_Subtype"=u."Aircraft_Series_Subtype"
  and c."Aircraft_Type_IATA"='763'
  and c."Aircraft_Series_Subtype"='300';

insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type,aircraft_subtype,version,object_path,sha256,byte_size,
   nose_arm_m,datum_description,datum_source,source_drawing,calibration)
values
  ('763','300',1,
   '763/300/c1f1363b79fdf599be92754af5dc30c2f81ef20bb4a2fe1995993e38ce825e27.svg',
   'c1f1363b79fdf599be92754af5dc30c2f81ef20bb4a2fe1995993e38ce825e27',
   144353,2.349500,
   'Station 0.0 is 92.5 inches (2.3495 m) forward of the airplane nose; body stations increase aft.',
   'FAA Type Certificate Data Sheet A1NM, Revision 40, Boeing 767 datum statement.',
   'User-supplied Boeing 767-300 DXF; original plan-view vector geometry isolated for application overlays.',
   '{"typeCode":"763","subtype":"300","length":2163,"noseArm":92.5,"armUnit":"IN","tailX":2231,"span":2139,"centreY":0,"imageFrame":{"x":92,"y":-150,"width":2189,"height":300},"cropLeft":92,"cropRight":2281,"holdY":-55,"holdHeight":110,"leftDoorY":-62,"rightDoorY":62,"labelCharWidth":0.58,"diagramCaption":"Boeing 767-300 master outline. Station 0.0 is fixed 92.5 inches forward of the airplane nose. Hold, door and cabin geometry will be added only from reviewed source data."}'::jsonb)
on conflict (aircraft_type,aircraft_subtype,version) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Families"
  (family_code,manufacturer,model)
values ('BOEING_767_300','Boeing','767-300')
on conflict (family_code) do update set
  manufacturer=excluded.manufacturer,
  model=excluded.model;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Versions"
  (family_code,version,source_layout_version_id,aircraft_length,nose_arm,arm_unit,source_description)
select 'BOEING_767_300',1,layout.id,2163.000000,92.500000,'IN',
  'Boeing 767-300 plan-view geometry from the supplied DXF; 92.5-inch nose datum from FAA TCDS A1NM Revision 40. Hold, door and cabin zones await reviewed source data.'
from "Basic_Carrier_Record"."Aircraft_Layout_Versions" layout
where layout.aircraft_type='763' and layout.aircraft_subtype='300' and layout.version=1
on conflict (family_code,version) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Active"(family_code,version_id)
select geometry.family_code,geometry.id
from "Basic_Carrier_Record"."Airframe_Geometry_Versions" geometry
where geometry.family_code='BOEING_767_300' and geometry.version=1
on conflict (family_code) do update set
  version_id=excluded.version_id,
  activated_at=now(),
  activated_by=auth.uid();

insert into "Basic_Carrier_Record"."Airframe_Geometry_Profiles"
  (geometry_version_id,profile_code,profile_name,door_layout,passenger_cabin,main_deck_cargo,rear_centre_tank,notes)
select active.version_id,'STANDARD','Standard passenger','STANDARD',true,false,false,
  'Baseline passenger airframe. Operational hold, door and cabin geometry must be added from reviewed source data.'
from "Basic_Carrier_Record"."Airframe_Geometry_Active" active
where active.family_code='BOEING_767_300'
on conflict (geometry_version_id,profile_code) do nothing;

insert into "Basic_Carrier_Record"."Airframe_Geometry_Decks"
  (geometry_version_id,profile_code,deck_code,deck_name,deck_purpose,display_order)
select active.version_id,'STANDARD',deck.code,deck.name,deck.purpose,deck.display_order
from "Basic_Carrier_Record"."Airframe_Geometry_Active" active
cross join (values
  ('MAIN','Main Deck','PASSENGER',1::smallint),
  ('LOWER','Lower Deck','CARGO',2::smallint)
) as deck(code,name,purpose,display_order)
where active.family_code='BOEING_767_300'
on conflict (geometry_version_id,profile_code,deck_code) do nothing;

insert into "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
  (aircraft_type,aircraft_subtype,family_code,profile_code)
values ('763','300','BOEING_767_300','STANDARD')
on conflict (aircraft_type,aircraft_subtype) do update set
  family_code=excluded.family_code,
  profile_code=excluded.profile_code,
  assigned_at=now(),
  assigned_by=auth.uid();

commit;
