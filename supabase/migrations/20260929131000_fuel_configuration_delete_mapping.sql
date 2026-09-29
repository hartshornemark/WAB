begin;
alter table "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" drop constraint "aircraft_registration_fuel_configuration_fk";
alter table "Basic_Carrier_Record"."Aircraft_Registration_Fuel_Configurations" add constraint "aircraft_registration_fuel_configuration_fk" foreign key("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code") references "Basic_Carrier_Record"."Aircraft_Fuel_System_Configurations"("Carrier_IATA","Aircraft_Type_IATA","Aircraft_Series_Subtype","Configuration_Code") on update cascade on delete cascade;
notify pgrst,'reload schema';
commit;
