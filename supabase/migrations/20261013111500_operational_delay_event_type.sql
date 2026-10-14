begin;

alter table "Basic_Carrier_Record"."Operational_Flight_Events"
  drop constraint "Operational_Flight_Events_Event_Type_check",
  add constraint "Operational_Flight_Events_Event_Type_check"
  check ("Event_Type" in ('CREATED', 'STATUS_CHANGED', 'UPDATED', 'DELAY_UPDATED'));

commit;
