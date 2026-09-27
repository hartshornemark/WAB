-- Keep the A350-900 forward hold start forward of its cargo-door opening.
-- Carrier D2 balance-arm values remain unchanged; only the drawing offset changes.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing, calibration)
values
  ('359', '900', 4, 'aircraft-layouts',
   '359/900/e479e387d87c3c901bfac79e3fb005e19275ced5bb3584d99a6b9c4a224d9781.svg', 'e479e387d87c3c901bfac79e3fb005e19275ced5bb3584d99a6b9c4a224d9781', 1129550, 1.84,
   'Station 0.0 is 1.84 m forward of the aircraft nose; balance arms increase aft.',
   'Carrier-supplied 1.84 m nose datum; Airbus A350-900 cargo geometry with the FWD hold start retained forward of the 2.90 m cargo-door opening, reviewed 27 September 2026.',
   'User-supplied Airbus_A350-900.dwg; original Airbus plan-view vector geometry isolated for application overlays.',
   '{"typeCode":"359","subtype":"900","length":66.8,"noseArm":1.84,"armUnit":"M","tailX":246.2,"span":239.8,"centreY":19.75,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":13.25,"holdHeight":13,"leftDoorY":12.75,"rightDoorY":26.75,"labelCharWidth":0.58,"holdArmOffsets":{"FWD":3.4},"diagramCaption":"Airbus A350-900 outline derived from the supplied Airbus plan drawing. The FWD hold begins forward of its cargo-door opening; AFT and bulk use the saved carrier Balance Arms."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
