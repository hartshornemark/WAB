alter table "Basic_Carrier_Record"."Aircraft_Holds"
 drop constraint "Aircraft_Holds_Name_check",
 add constraint "Aircraft_Holds_Name_check" check (
  (
   (btrim("Hold_Type")='BLK' and btrim("Hold_Display_Name") ~ '^[A-Z0-9]{1,3}$')
   or
   (btrim("Hold_Type")='ULD' and btrim("Hold_Display_Name") ~ '^[A-Z]{3}$')
  )
  and btrim("Hold_Name_ID")=upper(btrim("Hold_Deck_Location"))||':'||upper(btrim("Hold_Display_Name"))
 );
