# B5 ULD specifications verification — 17 September 2026

## Delivered
- Shared blue section header: **5. ULD SPECIFICATIONS (AHM565 Sheet B5)**.
- Master-list adoption with editable tare, maximum weight, maximum volume, and remarks; draft removal, Save and Cancel.
- Exactly one Default per adopted ULD type. Serial numbers and owner codes are excluded.
- Master values are KG/m³, converted to the carrier's B1 units on adoption. Stored carrier values convert when B1 units change.
- Supabase remains behind the repository port and infrastructure adapter.
- Approved migration `b5_uld_specifications` applied successfully.

## Checks passed
- 73 automated tests, TypeScript, ESLint, and production build.
- `uld-b5-checks.sql`: transactional checks for preserved values, adoption, default changes, missing/duplicate defaults, invalid weights/volume, unknown master codes, immutable carrier identity, stale edits, unit conversion, Solution Administrator and Carrier Administrator saving, and editor/cross-carrier/unassigned/anonymous denials. All test data and role fixtures rolled back.
- Browser: B4 Next opens B5 and the B5 Back link returns to B4; existing ZZ AKE loads; draft AVE adopts master values; Default selection switches; maximum below tare is rejected; Cancel discards draft; unchanged AKE saves successfully.
- Desktop form visually checked. Narrow 390px layout has no horizontal overflow; numeric fields are uniformly 48px high.
- Existing ZZ AKE retained: tare 90 KG, maximum 1588 KG, volume 4.3 m³, Default true.

## Security review and limits
- No B5 security-advisor findings. Existing project notices remain: [leaked-password protection disabled](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) and [11 internal/legacy tables with RLS enabled and no policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
- Functions are security-invoker, RLS remains authoritative, and anonymous execution is revoked.
- Sequential stale-revision checks passed; no multi-session concurrency stress test was performed.
- Preview moved to port 3007 because the older port-3006 process could not be stopped from this session.

## Precision and Add ULD correction
- Applied approved migration `b5_uld_precision`: whole-number tare and maximum weights; maximum volume up to two decimal places. Unit conversions round to those limits. Existing values preserved.
- Application input steps and validation match the database. Editing no longer displays six trailing decimal places.
- Master adoption rounds suggestions to the accepted precision. Add ULD now focuses and scrolls to the new entry and announces that Save is required.
- Updated automated tests, typecheck, lint and build passed. Updated rollback-only database suite passed precision rejection, conversion, and prior access checks.
- Browser verified AVE adoption, focused new entry, and Cancel. An intentionally invalid live browser Save test was blocked by automatic approval review; no workaround attempted. Precision validation was covered by automated and rollback-only SQL tests instead.
- Preview remains on port 3007 with original ZZ AKE values.

## Five-digit inventory serials — applied 18 September 2026

- Existing AKE serial range was normalized in place from `123–130` to `00123–00130`.
- A database trigger pads every future inserted or updated Start and End Serial to five digits.
- A rollback-only insert confirmed `7–19` is stored as `00007–00019`; no test row remained.
- The ULD screen displays saved inventory below its ULD specification in read mode.

## ULD inventory integration — applied 18 September 2026

- Connected `Carrier_ULD_Inventory` to B5 with a separate owning `Carrier_IATA`, preserving `ULD_IATA` as the printed Carrier Code, which may differ from the customer's IATA code.
- Added checkbox-controlled inventory ranges to each ULD. Controls default off and disabled; ADD supports further non-sequential ranges.
- Start and End Serial accept numeric text only, retain leading zeroes, and are limited to five characters. Carrier Code accepts two uppercase letters or numbers.
- Added primary/foreign keys, exact-range uniqueness, serial ordering and format checks, an owner index, immutable carrier ownership, four carrier-scoped RLS policies, and security-invoker read/save functions.
- Pre/post comparison confirmed ZZ AKE and P6P remained unchanged and the previously empty inventory table remained empty.
- `uld-b5-inventory-checks.sql` passed rollback-only save/read/remove, alternate Carrier Code, validation, RLS and anonymous-denial checks. The full B5 regression suite also passed.
- Application verification: 76 tests, TypeScript, ESLint and production build passed. Browser verified disabled defaults, activation, filtering `12A3456` to `12345`, uppercase Carrier Code, ADD, and Cancel without saving test data.
- Supabase security advisors reported no finding for `Carrier_ULD_Inventory`. Existing project notices remain: leaked-password protection is disabled, and 11 internal/legacy RLS tables have no policies.

## Carrier-specific ULD extension — applied and verified
- Added `Add a Carrier ULD`: code and type entry, followed by the existing weights, volume, Default and Remarks fields. No master entry is required for a carrier-specific draft.
- Existing master adoption remains available. Carrier-only codes can use a new type or share an existing type; duplicate codes and multiple defaults remain invalid.
- Applied migration `b5_carrier_specific_ulds` from `uld-b5-custom.sql`. Existing entries remain master-linked; generated nullable reference columns retain the master foreign key for adopted entries. Custom rows remain carrier-scoped under existing RLS and administrator permissions.
- 75 tests, TypeScript, ESLint and production build passed.
- Both `uld-b5-custom-checks.sql` and the updated B5 permission/precision suite passed with rollback-only test data. The original suite assumed one saved row; adjusted its adoption count to accommodate the user-added P6P.
- Browser verified Add a Carrier ULD, code Z9X/type NEW draft creation, default assignment and focus. Cancel discarded the test draft. Database save/read/removal verified transactionally.
- Preview restarted on port 3007. Existing AKE and P6P preserved; master list unchanged.
