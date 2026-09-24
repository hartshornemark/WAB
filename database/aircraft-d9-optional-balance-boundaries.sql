begin;
set local lock_timeout = '5s';
alter table "Basic_Carrier_Record"."Aircraft_Configurations"
  alter column "Cabin_Area_BA_Start" drop not null,
  alter column "Cabin_Area_BA_End" drop not null;
commit;
