drop policy if exists perm_aircraft_select on "Basic_Carrier_Record"."Aircraft_Compartments";
drop policy if exists perm_aircraft_insert on "Basic_Carrier_Record"."Aircraft_Compartments";
drop policy if exists perm_aircraft_update on "Basic_Carrier_Record"."Aircraft_Compartments";
drop policy if exists perm_aircraft_delete on "Basic_Carrier_Record"."Aircraft_Compartments";

create policy perm_aircraft_select on "Basic_Carrier_Record"."Aircraft_Compartments"
for select to authenticated
using (
  private.has_carrier_permission("Carrier_IATA"::text, 'AIRCRAFT_CONFIG_VIEW')
  or private.has_global_permission('AIRCRAFT_CONFIG_VIEW')
);

create policy perm_aircraft_insert on "Basic_Carrier_Record"."Aircraft_Compartments"
for insert to authenticated
with check (
  private.has_carrier_permission("Carrier_IATA"::text, 'AIRCRAFT_CONFIG_EDIT')
  or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')
);

create policy perm_aircraft_update on "Basic_Carrier_Record"."Aircraft_Compartments"
for update to authenticated
using (
  private.has_carrier_permission("Carrier_IATA"::text, 'AIRCRAFT_CONFIG_EDIT')
  or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')
)
with check (
  private.has_carrier_permission("Carrier_IATA"::text, 'AIRCRAFT_CONFIG_EDIT')
  or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')
);

create policy perm_aircraft_delete on "Basic_Carrier_Record"."Aircraft_Compartments"
for delete to authenticated
using (
  private.has_carrier_permission("Carrier_IATA"::text, 'AIRCRAFT_CONFIG_DELETE')
  or private.has_global_permission('AIRCRAFT_CONFIG_DELETE')
  or private.has_global_permission('AIRCRAFT_CONFIG_EDIT')
);
