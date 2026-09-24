# B1 Commodity Density Settings — 17 September 2026

Completed after explicit approval of database protections and integration/conversion. Migration: `b1_commodity_density_settings`. SQL record: `density-settings.sql`; rollback-only checks: `density-settings-checks.sql`.

## Storage and units

Uses the user's renamed columns in `Basic_Carrier_Record.Carrier_Units_of_Measure`: `Density_Checked_Baggage`, `Density_General_Cargo`, `Density_General_Mail`.

Values are stored in the selected B1 weight/volume units from `Basic_Carrier_Data`, not a permanently fixed KG/m³ basis. A database trigger converts saved non-null densities atomically when these selections change, using 1 lb = 0.45359237 kg and 1 ft³ = 0.028316846592 m³. Null remains unknown. Other legacy unit flags in Carrier_Units_of_Measure are not edited by this feature.

## Integration and protection

B1 includes a Commodity Density Settings section with Edit Densities / Save / Cancel. Positive decimal values or blank are supported. Original ZZ values remain 176, 212, 212 KG/m³.

The architecture retains domain validation, application authentication/carrier checks, repository port, and request-scoped Supabase adapter. Invoker-only read/save functions enforce RLS. Saves lock the basic carrier row then the density row and compare a revision, serialising unit conversion with density saves. Carrier identity is immutable; carrier foreign key and finite-positive checks are enforced in the database. Writes to the units table now require Solution Administrator or Carrier Administrator authority; existing authorised read access is preserved.

## Verification

- All 68 automated tests, lint, TypeScript and production build passed.
- Live rollback-only database checks passed: administrator reads/writes, blank values, zero/negative/NaN rejection, immutable carrier, stale-save rejection, KG/m³ to LB/ft³ conversion and reverse conversion, read-only Configuration Editor, cross-carrier denial, unassigned read denial and anonymous denial.
- Browser verified initial values, zero rejection, successful saving of unchanged values, reload persistence and desktop/narrow-screen layout.
- All density/unit/role test changes were rolled back; final live values remain unchanged.
- Security advisor: no new findings. Existing informational RLS-without-policy notices on internal/legacy tables remain; [leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains disabled.

This implements density configuration and unit conversion, not a load-control calculation engine. External consumers must apply their own approved fallback calculation. Multi-session concurrency stress testing was not performed.
