-- Align the aft edge of A350-900 Compartment 3 with the forward/start edge of the aft cargo door.
-- The AFT hold outer limits and all carrier D2 values remain unchanged.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing, calibration)
values
  ('359', '900', 5, 'aircraft-layouts',
   '359/900/e19de06214103b3c2173905ae2952e01c051541cce043a889af4370762671d99.svg', 'e19de06214103b3c2173905ae2952e01c051541cce043a889af4370762671d99', 1129539, 1.84,
   'Station 0.0 is 1.84 m forward of the aircraft nose; balance arms increase aft.',
   'Carrier-supplied 1.84 m nose datum; Airbus A350-900 cargo geometry with the aft edge of Compartment 3 aligned to the forward edge of the aft cargo door, reviewed 27 September 2026.',
   'User-supplied Airbus_A350-900.dwg; original Airbus plan-view vector geometry isolated for application overlays.',
   '{"typeCode":"359","subtype":"900","length":66.8,"noseArm":1.84,"armUnit":"M","tailX":246.2,"span":239.8,"centreY":19.75,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":13.25,"holdHeight":13,"leftDoorY":12.75,"rightDoorY":26.75,"labelCharWidth":0.58,"holdArmOffsets":{"FWD":3.4},"holdSubdivisionBreaks":{"AFT":[51.71]},"diagramCaption":"Airbus A350-900 outline derived from the supplied Airbus plan drawing. The FWD hold begins forward of its door; the aft edge of Compartment 3 aligns with the aft cargo-door start."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
