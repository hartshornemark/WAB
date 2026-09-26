-- Provisional 737-800 template using the user-approved MAX 9 datum framework.
-- Activation follows local SVG checksum verification and Storage upload.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing,
   calibration)
values
  ('738', '800', 1, 'aircraft-layouts',
   '738/800/059f7cf1215e18e1b2989210c4802c7b3b01300f1e4b11120894708a7da117db.svg',
   '059f7cf1215e18e1b2989210c4802c7b3b01300f1e4b11120894708a7da117db',
   87588, 3.302,
   'Provisional: datum zero 130 inches (3.302 m) forward of nose, matching the approved 737 MAX 9 calibration framework.',
   'User-directed reuse of the approved 737 MAX 9 130-inch calibration for the Boeing 737-800 overlay, 26 September 2026. Weight-and-balance applicability is provisional pending carrier source confirmation.',
   'User-supplied 737-800.dxf. Top-view vector geometry and the published 129 ft 6 in overall length were used to construct the fuselage overlay.',
   '{"typeCode":"738","subtype":"800","length":1554,"noseArm":130,"armUnit":"IN","tailX":244,"span":240,"centreY":25,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":15,"holdHeight":20,"leftDoorY":12,"rightDoorY":38,"labelCharWidth":0.58,"diagramCaption":"Provisional 737-800 calibration: nose at balance arm 130 inches. Fuselage outline derived from the supplied 737-800 top view."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
