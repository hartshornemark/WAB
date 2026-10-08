create index if not exists operational_freight_acceptance_items_carrier_idx
  on "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items" ("Carrier_IATA");
