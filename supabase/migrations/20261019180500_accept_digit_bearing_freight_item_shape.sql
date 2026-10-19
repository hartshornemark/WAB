begin;

alter table "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items"
  drop constraint "operational_freight_acceptance_item_shape";

alter table "Basic_Carrier_Record"."Operational_Freight_Acceptance_Items"
  add constraint "operational_freight_acceptance_item_shape" check(
    ("Load_Type"='ULD' and "ULD_ID"~'^[A-Z0-9]{3}[A-Z0-9]{4,8}$' and "Volume_M3" is null)
    or ("Load_Type"='BULK' and "ULD_ID" is null)
  );

commit;
