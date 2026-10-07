do $migration$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('"Basic_Carrier_Record".save_aircraft_d2(text,text,text,text,text,jsonb)'::regprocedure);updated:=definition;
 updated:=replace(updated,$old$(section_code='BULK' and hold_name !~ '^[A-Z0-9]{1,3}$')$old$,$new$(section_code='BULK' and hold_name not in ('FWD','AFT','FLF','FLA','FLM','ALF','ALA','ALM','ALB'))$new$);
 if updated=definition then raise exception 'save_aircraft_d2 Bulk Hold rule changed';end if;
 execute updated;
end $migration$;

alter table "Basic_Carrier_Record"."Aircraft_Holds"
 drop constraint "Aircraft_Holds_Name_check",
 add constraint "Aircraft_Holds_Name_check" check (
  (
   (btrim("Hold_Type")='BLK' and btrim("Hold_Display_Name") in ('FWD','AFT','FLF','FLA','FLM','ALF','ALA','ALM','ALB'))
   or
   (btrim("Hold_Type")='ULD' and btrim("Hold_Display_Name") ~ '^[A-Z]{3}$')
  )
  and btrim("Hold_Name_ID")=upper(btrim("Hold_Deck_Location"))||':'||upper(btrim("Hold_Display_Name"))
 ) not valid;
