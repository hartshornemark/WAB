-- Publish a new immutable A350-900 calibration in which bulk Hold 5 follows
-- the narrowing aft fuselage. Longitudinal limits remain the saved D2 arms.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing, calibration)
values
  ('359', '900', 7, 'aircraft-layouts',
   '359/900/e8c777607358d94758826b32170b414122a650e217671f10aacd459fe3850ed3.svg', 'e8c777607358d94758826b32170b414122a650e217671f10aacd459fe3850ed3', 1129562, 1.84,
   'Station 0.0 is 1.84 m forward of the aircraft nose; balance arms increase aft.',
   'Carrier-supplied 1.84 m nose datum, saved D4 cargo-door positions and a tapered bulk-hold profile fitted within the supplied Airbus plan view, reviewed 27 September 2026.',
   'User-supplied Airbus_A350-900.dwg; original Airbus plan-view vector geometry isolated for application overlays.',
   '{"typeCode":"359","subtype":"900","length":66.8,"noseArm":1.84,"armUnit":"M","tailX":246.2,"span":239.8,"centreY":19.75,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":13.25,"holdHeight":13,"leftDoorY":12.75,"rightDoorY":26.75,"labelCharWidth":0.58,"holdArmOffsets":{"FWD":3.4},"holdSubdivisionBreaks":{"AFT":[51.71]},"holdSubdivisionDoorStarts":{"AFT":["AFT"]},"holdProfiles":{"5":{"points":[{"arm":54.09,"halfWidth":6.0},{"arm":55.0,"halfWidth":5.45},{"arm":56.59,"halfWidth":4.25}]}},"diagramCaption":"Airbus A350-900 outline derived from the supplied Airbus plan drawing. Hold 5 follows the taper of the aft fuselage; the FWD hold begins forward of its door and the aft edge of Compartment 3 follows the saved D4 AFT-door start."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
