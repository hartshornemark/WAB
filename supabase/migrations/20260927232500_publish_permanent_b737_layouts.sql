-- Permanent Boeing 737 layout publications. The common datum authority is
-- Boeing 737 AMM Task 06-21-00: STA 0 is 130.0 inches forward of the nose.
insert into "Basic_Carrier_Record"."Aircraft_Layout_Versions"
  (aircraft_type, aircraft_subtype, version, bucket, object_path, sha256,
   byte_size, nose_arm_m, datum_description, datum_source, source_drawing, calibration)
values
  ('738','800',5,'aircraft-layouts',
   '738/800/a982979d7638c8c99028f0b1936caf6308408ed767deb29047eb8610c797c016.svg','a982979d7638c8c99028f0b1936caf6308408ed767deb29047eb8610c797c016',114173,3.302,
   'Datum plane is perpendicular to the fuselage centreline and positioned 130.0 inches (3.302 m) forward of the airplane nose.',
   'Boeing 737 Airplane Maintenance Manual, AMM Task 06-21-00, Dimensions and Areas / Standard Practices.',
   'User-supplied 737-800.dxf. Top-view vector geometry and the published 129 ft 6 in overall length were used to construct the fuselage overlay.',
   '{"typeCode":"738","subtype":"800","length":1554,"noseArm":130,"armUnit":"IN","tailX":244,"span":240,"centreY":25,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":18,"holdHeight":14,"leftDoorY":18,"rightDoorY":32,"labelCharWidth":0.58,"diagramCaption":"Boeing 737-800 outline. Datum plane is 130.0 inches forward of the airplane nose in accordance with Boeing 737 AMM Task 06-21-00; the KA drawing-origin correction preserves station alignment."}'::jsonb),
  ('7M9','900',2,'aircraft-layouts',
   '7M9/900/dfcf9a6695f65d1104917482a29b0af26efa3df33c6f369a755a51a3b8540b40.svg','dfcf9a6695f65d1104917482a29b0af26efa3df33c6f369a755a51a3b8540b40',360377,3.302,
   'Datum plane is perpendicular to the fuselage centreline and positioned 130.0 inches (3.302 m) forward of the airplane nose.',
   'Boeing 737 Airplane Maintenance Manual, AMM Task 06-21-00, Dimensions and Areas / Standard Practices.',
   'Boeing 737-9_3VIEW.dwg, copyright 2020. Recovered original top-view curves; airport-planning accuracy +/-6 inches.',
   '{"typeCode":"7M9","subtype":"900","length":1659.9191,"noseArm":130,"armUnit":"IN","tailX":244,"span":240,"centreY":25,"imageFrame":{"x":0,"y":0,"width":248,"height":50},"cropLeft":0,"cropRight":248,"holdY":15,"holdHeight":20,"leftDoorY":12,"rightDoorY":38,"labelCharWidth":0.58,"diagramCaption":"Boeing 737 MAX 9 airport-planning outline. Datum plane is 130.0 inches forward of the airplane nose in accordance with Boeing 737 AMM Task 06-21-00."}'::jsonb)
on conflict (aircraft_type,aircraft_subtype,version) do nothing;
