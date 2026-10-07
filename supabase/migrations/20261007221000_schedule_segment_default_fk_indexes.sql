begin;

create index "schedule_segment_defaults_departure_airport_idx"
  on "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults"("Departure_Airport_IATA");

create index "schedule_segment_defaults_arrival_airport_idx"
  on "Basic_Carrier_Record"."Schedule_Segment_Load_Control_Defaults"("Arrival_Airport_IATA");

commit;
