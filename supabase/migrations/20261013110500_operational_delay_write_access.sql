begin;

grant update ("Delay_Minutes", "Version", "Updated_At")
on table "Basic_Carrier_Record"."Operational_Flights"
to authenticated;

grant insert (
  "Operational_Flight_ID",
  "Carrier_IATA",
  "Event_Type",
  "Previous_Status",
  "New_Status",
  "Event_Data",
  "Actor_User_ID"
)
on table "Basic_Carrier_Record"."Operational_Flight_Events"
to authenticated;

create policy operational_flights_delay_update
on "Basic_Carrier_Record"."Operational_Flights"
for update
to authenticated
using (
  (select private.has_carrier_permission("Carrier_IATA", 'LOAD_CONTROL_OPERATE'))
  or (select private.has_global_permission('LOAD_CONTROL_OPERATE'))
)
with check (
  (select private.has_carrier_permission("Carrier_IATA", 'LOAD_CONTROL_OPERATE'))
  or (select private.has_global_permission('LOAD_CONTROL_OPERATE'))
);

create policy operational_flight_events_delay_insert
on "Basic_Carrier_Record"."Operational_Flight_Events"
for insert
to authenticated
with check (
  "Event_Type" = 'DELAY_UPDATED'
  and "Actor_User_ID" = (select auth.uid())
  and (
    (select private.has_carrier_permission("Carrier_IATA", 'LOAD_CONTROL_OPERATE'))
    or (select private.has_global_permission('LOAD_CONTROL_OPERATE'))
  )
);

commit;
