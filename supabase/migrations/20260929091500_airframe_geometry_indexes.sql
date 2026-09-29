-- Supports activation checks and family/profile resolution without scanning
-- every aircraft identity assignment.
create index "Aircraft_Airframe_Geometry_Assignments_family_profile_idx"
on "Basic_Carrier_Record"."Aircraft_Airframe_Geometry_Assignments"
  (family_code, profile_code);
