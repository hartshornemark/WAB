-- Version 3 aligns the SVG to the actual top-view fuselage centreline from
-- the source DXF. Version 2's overlay band was centred, but the drawing was not.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing,
   calibration)
values
  ('738', '800', 3, 'aircraft-layouts',
   '738/800/23b9d40018606ca7793cc606a2cc938d7e122034511fd8c957d2c820e75ada5b.svg',
   '23b9d40018606ca7793cc606a2cc938d7e122034511fd8c957d2c820e75ada5b',
   114050, 3.302,
   'Provisional: datum zero 130 inches (3.302 m) forward of nose, matching the approved 737 MAX 9 calibration framework.',
   'User-directed reuse of the approved 737 MAX 9 130-inch calibration for the Boeing 737-800 overlay, 26 September 2026. Weight-and-balance applicability is provisional pending carrier source confirmation.',
   'User-supplied 737-800.dxf. Top-view fuselage geometry is centred on the two forward-most outline curves; the published 129 ft 6 in overall length controls longitudinal scale.',
   '{"typeCode":"738","subtype":"800","length":1554,"noseArm":130,"armUnit":"IN","tailX":244,"span":240,"centreY":25,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":20,"holdHeight":10,"leftDoorY":18,"rightDoorY":32,"labelCharWidth":0.58,"diagramCaption":"Provisional 737-800 calibration: physical datum 130 inches forward of the nose; KA plotting uses the matching -130-inch drawing-origin correction."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
