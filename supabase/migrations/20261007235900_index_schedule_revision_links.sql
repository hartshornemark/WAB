create index "flight_schedule_supersedes_import_idx"
  on "Basic_Carrier_Record"."Flight_Schedule_Imports"("Supersedes_Import_ID")
  where "Supersedes_Import_ID" is not null;
