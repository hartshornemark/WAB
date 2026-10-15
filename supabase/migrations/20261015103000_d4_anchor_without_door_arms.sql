alter table "Basic_Carrier_Record"."Aircraft_Holds"
 drop constraint if exists "Aircraft_Holds_Door_Core_All_Or_None_check";

alter table "Basic_Carrier_Record"."Aircraft_Holds"
 add constraint "Aircraft_Holds_Door_Core_Or_Anchor_check" check (
  (
   "Hold_DOOR_Start" is null
   and "Hold_DOOR_End" is null
   and "Hold_DOOR_Height" is null
   and "Hold_DOOR_Orientation" is null
   and "Hold_DOOR_Anchor_Type" is null
   and "Hold_DOOR_Anchor_Ref" is null
  )
  or
  (
   "Hold_DOOR_Orientation" is not null
   and (
    ("Hold_DOOR_Start" is null and "Hold_DOOR_End" is null)
    or
    ("Hold_DOOR_Start" is not null and "Hold_DOOR_End" is not null)
   )
   and (
    ("Hold_DOOR_Anchor_Type" is null and "Hold_DOOR_Anchor_Ref" is null)
    or
    ("Hold_DOOR_Anchor_Type" is not null and "Hold_DOOR_Anchor_Ref" is not null)
   )
   and ("Hold_DOOR_Start" is not null or "Hold_DOOR_Anchor_Type" is not null)
  )
 );
