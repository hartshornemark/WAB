# B2 verification

## Implementation and database checks — 16 September 2026

- Applied crew-weights.sql to project ffmadtrcirrzywdqahbu with explicit user approval.
- Existing values preserved; no columns added by the application migration.
- Exact label: Crew Weights include Hand Baggage.
- Separate flight-deck and cabin-crew hand-baggage fields are inactive when included; both are required when excluded. Inactive stored values are retained.
- Positive integer crew weights; nonnegative optional baggage weights; null remains distinct from zero.
- SQL APIs use SECURITY INVOKER and RLS. Solution Administrators and Carrier Administrators can save; other authorised users remain read-only.
- Lint, type checks, production build and all 51 automated tests passed.
- crew-role-checks.sql passed with rollback: conditional hand baggage, numeric constraints, retained inactive values, null/zero, initial insert, stale data and unit rejection, administrator save, editor write denial, cross-carrier denial and anonymous denial.
- Security advisor: no new findings; existing internal/legacy default-deny INFO notices and disabled leaked-password protection warning remain.

## Final browser checks — 17 September 2026

- Existing ZZ values displayed: flight-deck male/female 85 KG; cabin male/female 75 KG; other baggage weights 0; hand baggage included.
- Edit exposes checkbox; hand-baggage inputs initially disabled and empty.
- Unchecking enables both fields. Saving with missing hand-baggage values displays validation and leaves the draft open.
- Draft values 5 and 4 retained when checked (disabled) and unchecked again (enabled).
- Cancel discards those draft values. Re-entering edit shows original blank hand-baggage inputs and checked checkbox.
- Saved the original unchanged values through the application. Success message displayed; reload returned the same stored values. No test weights were saved.
- B2 back link returns directly to B1, and B1 Next links to B2.
- Visual review confirmed blue focus/checkbox styling, strong section breaks, aligned numeric fields, and readable inactive styling.

Scope: one carrier-wide set of crew weights, plus Long Haul / Short Haul / Other baggage weights. Remarks and operation-specific crew-weight variants are not part of this implementation.

## Flight category selection — 17 September 2026

Applied approved migration `crew_hold_baggage_flight_categories` to ffmadtrcirrzywdqahbu. Added three saved category flags, exclusive All Flights validation, and required weights for selected categories. Existing numeric weights preserved; existing records start with no category selected pending administrator review.

- Current Supabase documentation and changelog reviewed.
- `crew-hold-checks.sql`: passed save/read round trips, exclusivity, independent Longhaul/Shorthaul, required active weights, retained inactive weights, and direct table constraints. Test changes rolled back.
- `crew-role-checks.sql`: passed administrator saves, editor/cross-carrier/anonymous denials and existing crew validation regression checks. Test changes rolled back.
- Lint, TypeScript, all 53 tests and production build passed.
- Refreshed browser on port 3006: requested text and category order present; All Flights disables Longhaul/Shorthaul; Longhaul and Shorthaul can both be selected and enable their weights; Cancel restores saved selections.
- Security advisor retains the existing 11 informational default-deny table notices and the existing leaked-password-protection warning; no new findings reported.
