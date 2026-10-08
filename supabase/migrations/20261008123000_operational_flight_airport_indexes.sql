begin;

create index "operational_flights_departure_airport_idx"
  on "Basic_Carrier_Record"."Operational_Flights"("Departure_Airport_IATA");

create index "operational_flights_arrival_airport_idx"
  on "Basic_Carrier_Record"."Operational_Flights"("Arrival_Airport_IATA");

commit;
