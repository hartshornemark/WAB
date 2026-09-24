begin;

alter table "Basic_Carrier_Record"."Aircraft_Special_Load_Limits"
  drop constraint if exists "Aircraft_Special_Load_Limits_Maximum_Quantity_check",
  add constraint "Aircraft_Special_Load_Limits_Maximum_Quantity_check"
    check ("Maximum_Quantity" >= 0);

comment on column "Basic_Carrier_Record"."Aircraft_Special_Load_Limits"."Maximum_Quantity"
  is 'Maximum permitted quantity. Zero explicitly prohibits the Special Load for the selected hold and optional location; no row means unrestricted.';

commit;
