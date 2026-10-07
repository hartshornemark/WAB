-- The passenger A321-200 shares the locked A321 airframe outline with the
-- standard passenger geometry profile.
insert into "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
  (aircraft_type,aircraft_subtype,family_code,profile_code)
values ('321','200','AIRBUS_A321','STANDARD')
on conflict (aircraft_type,aircraft_subtype) do update
set family_code=excluded.family_code,profile_code=excluded.profile_code;
