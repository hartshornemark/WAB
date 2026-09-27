-- Correct the A350-900 datum, drawing anchors and fuselage centreline.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing, calibration)
values
  ('359', '900', 2, 'aircraft-layouts',
   '359/900/25b6373b445b76857d54490a9dfbbe8a1f5a9c0afbe95cb8f89fb3a5ce0728e6.svg', '25b6373b445b76857d54490a9dfbbe8a1f5a9c0afbe95cb8f89fb3a5ce0728e6', 1129505, 1.84,
   'Station 0.0 is 1.84 m forward of the aircraft nose; balance arms increase aft.', 'Carrier-supplied A350-900 datum confirmation and ZZ C4 configuration, 27 September 2026.', 'User-supplied Airbus_A350-900.dwg; original Airbus plan-view vector geometry isolated for application overlays.',
   '{"typeCode":"359","subtype":"900","length":66.8,"noseArm":1.84,"armUnit":"M","tailX":246.2,"span":239.8,"centreY":19.75,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":13.25,"holdHeight":13,"leftDoorY":12.75,"rightDoorY":26.75,"labelCharWidth":0.58,"diagramCaption":"Airbus A350-900 outline derived from the supplied Airbus plan drawing. The nose is at Balance Arm 1.84 m; overlays follow the saved carrier station system."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
