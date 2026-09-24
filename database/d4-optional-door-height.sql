begin;

alter table "Basic_Carrier_Record"."Aircraft_Holds"
  drop constraint if exists "Aircraft_Holds_Door_All_Or_None_check";

alter table "Basic_Carrier_Record"."Aircraft_Holds"
  add constraint "Aircraft_Holds_Door_Core_All_Or_None_check" check (
    ("Hold_DOOR_Start" is null and "Hold_DOOR_End" is null and "Hold_DOOR_Orientation" is null)
    or
    ("Hold_DOOR_Start" is not null and "Hold_DOOR_End" is not null and "Hold_DOOR_Orientation" is not null)
  );

commit;
