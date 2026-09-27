-- Use the saved D4 AFT-door start as the A350-900 Compartment 3 aft boundary.
-- The stored 51.71 m master value remains the fallback when D4 is unavailable.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing, calibration)
values
  ('359', '900', 6, 'aircraft-layouts',
   '359/900/eafdbd501fb08a6e3cce6459285f4a1eed034939ab598b6ca964f340ea39a51a.svg', 'eafdbd501fb08a6e3cce6459285f4a1eed034939ab598b6ca964f340ea39a51a', 1129601, 1.84,
   'Station 0.0 is 1.84 m forward of the aircraft nose; balance arms increase aft.',
   'Carrier-supplied 1.84 m nose datum and saved D4 cargo-door positions; Compartment 3 uses the current AFT door start, reviewed 27 September 2026.',
   'User-supplied Airbus_A350-900.dwg; original Airbus plan-view vector geometry isolated for application overlays.',
   '{"typeCode":"359","subtype":"900","length":66.8,"noseArm":1.84,"armUnit":"M","tailX":246.2,"span":239.8,"centreY":19.75,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":13.25,"holdHeight":13,"leftDoorY":12.75,"rightDoorY":26.75,"labelCharWidth":0.58,"holdArmOffsets":{"FWD":3.4},"holdSubdivisionBreaks":{"AFT":[51.71]},"holdSubdivisionDoorStarts":{"AFT":["AFT"]},"diagramCaption":"Airbus A350-900 outline derived from the supplied Airbus plan drawing. The FWD hold begins forward of its door; the aft edge of Compartment 3 follows the saved D4 AFT-door start."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
