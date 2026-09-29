begin;
create index "aircraft_balance_condition_fuel_configuration_idx" on "Basic_Carrier_Record"."Aircraft_Balance_Envelope_Conditions"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Fuel_Configuration_Code");
notify pgrst,'reload schema';
commit;
