-- Version 4 increases the hold overlay depth while retaining the verified
-- longitudinal calibration. The D4 door ranges 244-292 and 1009-1057 inches
-- independently align with the forward and aft cargo doors in the source SVG.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing,
   calibration)
values
  ('738', '800', 4, 'aircraft-layouts',
   '738/800/4dba08f753174ac431c0dcf594651c7b5180c496019d077a8fae0e0a87df4754.svg',
   '4dba08f753174ac431c0dcf594651c7b5180c496019d077a8fae0e0a87df4754',
   114050, 3.302,
   'Provisional: datum zero 130 inches (3.302 m) forward of nose, matching the approved 737 MAX 9 calibration framework.',
   'User-directed reuse of the approved 737 MAX 9 130-inch calibration for the Boeing 737-800 overlay, 26 September 2026. Weight-and-balance applicability is provisional pending carrier source confirmation.',
   'User-supplied 737-800.dxf. Top-view fuselage geometry is centred on the two forward-most outline curves; the published 129 ft 6 in overall length controls longitudinal scale. D4 door ranges 244-292 and 1009-1057 inches confirm the carrier plotting origin.',
   '{"typeCode":"738","subtype":"800","length":1554,"noseArm":130,"armUnit":"IN","tailX":244,"span":240,"centreY":25,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":18,"holdHeight":14,"leftDoorY":18,"rightDoorY":32,"labelCharWidth":0.58,"diagramCaption":"Provisional 737-800 calibration: physical datum 130 inches forward of the nose; KA plotting uses the matching -130-inch drawing-origin correction."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
