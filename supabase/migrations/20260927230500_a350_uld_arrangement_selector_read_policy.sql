create policy aircraft_layout_uld_arrangements_read
on "Basic_Carrier_Record"."Aircraft_Layout_ULD_Arrangement_Selectors"
for select to authenticated
using (private.can_view_aircraft_layout(aircraft_type, aircraft_subtype));

grant select on "Basic_Carrier_Record"."Aircraft_Layout_ULD_Arrangement_Selectors" to authenticated;
