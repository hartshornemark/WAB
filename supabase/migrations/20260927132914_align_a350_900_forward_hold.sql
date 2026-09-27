-- Align the A350-900 forward hold to the aircraft drawing's cargo-door anchor.
-- Carrier D2 balance-arm limits remain unchanged; this is a drawing-only offset.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing, calibration)
values
  ('359', '900', 3, 'aircraft-layouts',
   '359/900/e9f41f582684cd2e7640203e325d6b349f61ce829c7104390edea2b1dcae3d29.svg', 'e9f41f582684cd2e7640203e325d6b349f61ce829c7104390edea2b1dcae3d29', 1129531, 1.84,
   'Station 0.0 is 1.84 m forward of the aircraft nose; balance arms increase aft.',
   'Carrier-supplied 1.84 m nose datum; Airbus A350-900 Aircraft Characteristics cargo-compartment geometry and 2.90 m forward cargo-door anchor, reviewed 27 September 2026.',
   'User-supplied Airbus_A350-900.dwg; original Airbus plan-view vector geometry isolated for application overlays.',
   '{"typeCode":"359","subtype":"900","length":66.8,"noseArm":1.84,"armUnit":"M","tailX":246.2,"span":239.8,"centreY":19.75,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":13.25,"holdHeight":13,"leftDoorY":12.75,"rightDoorY":26.75,"labelCharWidth":0.58,"holdArmOffsets":{"FWD":6.75},"diagramCaption":"Airbus A350-900 outline derived from the supplied Airbus plan drawing. The FWD hold uses the Airbus A350-900 cargo-door anchor; AFT and bulk use the saved carrier Balance Arms."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
