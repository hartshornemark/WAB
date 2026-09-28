-- Defaults belong to a carrier aircraft variant, not to the carrier as a whole.
drop index "Basic_Carrier_Record".carrier_uld_one_default;
create unique index carrier_uld_one_default
  on "Basic_Carrier_Record"."Carrier_ULD_Specifications"
  ("Carrier_IATA", "Aircraft_Type_IATA", "Aircraft_Series_Subtype", "ULD_Type")
  where "ULD_Default";
