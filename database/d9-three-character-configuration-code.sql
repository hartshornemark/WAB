begin;

alter table "Basic_Carrier_Record"."Aircraft_Configurations"
  drop constraint if exists "Aircraft_Configurations_Code_check";

alter table "Basic_Carrier_Record"."Aircraft_Configurations"
  alter column "Configuration_Code" type varchar(3)
  using btrim("Configuration_Code");

alter table "Basic_Carrier_Record"."Aircraft_Configurations"
  add constraint "Aircraft_Configurations_Code_check"
  check (btrim("Configuration_Code") ~ '^[A-Z0-9]{1,3}$');

commit;
