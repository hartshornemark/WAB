-- Publish the Airbus A350-900 plan-view drawing and its paired metric calibration.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing, calibration)
values
  ('359', '900', 1, 'aircraft-layouts',
   '359/900/5a7d5364c1cd7ef7fbfacaa6a168fcb4b53acac04a32021ba60f2ab252746414.svg', '5a7d5364c1cd7ef7fbfacaa6a168fcb4b53acac04a32021ba60f2ab252746414', 1129428, 0,
   'Carrier C4 datum zero is at the aircraft nose; balance arms increase aft.', 'Carrier ZZ C4 configuration reviewed 27 September 2026. The master drawing geometry does not independently define the weight-and-balance datum.', 'User-supplied Airbus_A350-900.dwg; original Airbus plan-view vector geometry isolated for application overlays.',
   '{"typeCode":"359","subtype":"900","length":66.8,"noseArm":0,"armUnit":"M","tailX":244,"span":240,"centreY":25,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":17,"holdHeight":16,"leftDoorY":16,"rightDoorY":34,"labelCharWidth":0.58,"diagramCaption":"Airbus A350-900 outline derived from the supplied Airbus plan drawing. Longitudinal plotting follows the saved carrier C4 datum."}'::jsonb)
on conflict (aircraft_type, aircraft_subtype, version) do nothing;
