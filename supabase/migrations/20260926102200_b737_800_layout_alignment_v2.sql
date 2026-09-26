-- Version 2 narrows the hold band to the fuselage and pairs KA's Boeing
-- station arms with the same -130-inch drawing-origin correction used by MAX 9.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing,
   calibration)
values
  ('738', '800', 2, 'aircraft-layouts',
   '738/800/8a16fbaf865ea9e6b48f922a48060c604dec56768f7d9cb9e2ed3df51f7445da.svg',
   '8a16fbaf865ea9e6b48f922a48060c604dec56768f7d9cb9e2ed3df51f7445da',
   87586, 3.302,
   'Provisional: datum zero 130 inches (3.302 m) forward of nose, matching the approved 737 MAX 9 calibration framework.',
   'User-directed reuse of the approved 737 MAX 9 130-inch calibration for the Boeing 737-800 overlay, 26 September 2026. Weight-and-balance applicability is provisional pending carrier source confirmation.',
   'User-supplied 737-800.dxf. Top-view vector geometry and the published 129 ft 6 in overall length were used to construct the fuselage overlay.',
   '{"typeCode":"738","subtype":"800","length":1554,"noseArm":130,"armUnit":"IN","tailX":244,"span":240,"centreY":25,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":20,"holdHeight":10,"leftDoorY":18,"rightDoorY":32,"labelCharWidth":0.58,"diagramCaption":"Provisional 737-800 calibration: physical datum 130 inches forward of the nose; KA plotting uses the matching -130-inch drawing-origin correction."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
