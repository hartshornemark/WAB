begin;

alter table "Basic_Carrier_Record"."Basic_Aircraft_Data"
  add constraint "basic_aircraft_maximum_weight_order" check (
    ("MZFW" is null or "MLAW" is null or "MZFW"<="MLAW") and
    ("MLAW" is null or "MTOW" is null or "MLAW"<="MTOW") and
    ("MTOW" is null or "MRW" is null or "MTOW"<="MRW")
  );



notify pgrst,'reload schema';
commit;

