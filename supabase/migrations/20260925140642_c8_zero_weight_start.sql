-- Fuel schedules may start at zero fuel weight. Negative weights remain invalid.
ALTER TABLE "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" DROP CONSTRAINT aircraft_fuel_standard_weight_positive;
ALTER TABLE "Basic_Carrier_Record"."Aircraft_Fuel_Loading_STANDARD" ADD CONSTRAINT aircraft_fuel_standard_weight_nonnegative CHECK ("Fuel_Weight" >= 0);
