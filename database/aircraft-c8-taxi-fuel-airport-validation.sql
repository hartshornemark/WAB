begin;
alter table "Basic_Carrier_Record"."Carrier_Taxi_Fuel"
 drop constraint carrier_taxi_fuel_airport_valid,
 add constraint carrier_taxi_fuel_airport_valid check (
  ("Default" and "Airport_IATA" is null)
  or
  (not "Default" and "Airport_IATA" is not null and "Airport_IATA" ~ '^[A-Z]{3}$')
 );
commit;
