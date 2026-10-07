begin;

create index if not exists "scheduled_flight_legs_source_record_fk_idx"
  on "Basic_Carrier_Record"."Scheduled_Flight_Legs"
    ("Import_ID","Carrier_IATA","Source_Line_Number");

commit;
