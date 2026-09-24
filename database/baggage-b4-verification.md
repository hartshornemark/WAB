# B4 database corrections — 17 September 2026

Applied to project `ffmadtrcirrzywdqahbu` after explicit user approval, migration `b4_baggage_planning_corrections`. Implementation: `baggage-b4-corrections.sql`; rollback-only verification: `baggage-b4-checks.sql`.

## Result

- Corrected table spelling to `Carrier_Baggage_Weights_BYCLASS` and identifier to `Baggage_Weight_Set_ID`.
- Preserved existing per-piece defaults: ZZ male 15, female 15, child 10, standard all 15; summer/winter remain null.
- Added a protected All Flights / All Classes baseline. Identity and labels cannot change, and the baseline cannot be deleted. Administrators can edit weight values. Per-passenger baseline remains UNSET/null until configured; no operational weight was invented.
- Added passenger-category scope and standard/actual method support. Per-piece defaults remain sourced from ALLFLIGHTS, with explicit class/variation overrides supported.
- Corrected planning primary key, added carrier and variation foreign keys, unique scope constraints, nonnegative finite decimal validation and remarks limits. Class membership and reverse-reference triggers protect the existing wide class table.
- RLS allows authorised reads and limits writes to Solution Administrators and Carrier Administrators. No application_security tables were exposed.

## Live verification

The rollback-only SQL suite passed baseline identity/deletion protection, preserved defaults, required and nonnegative weights, standard/actual modes, exact decimal planning values, class and variation references, duplicate prevention, administrator edits, Configuration Editor write denial, cross-carrier denial, unassigned read denial and anonymous denial.

After rollback, confirmed exactly one ZZ baseline with UNSET/null per-passenger weight, unchanged original per-piece values, zero planning records, no temporary TST variation and no temporary test organisation.

Supabase security advisor reported no B4 findings. Existing findings remain: eleven informational RLS-without-policy notices on internal/legacy tables and disabled leaked-password protection. See [password protection guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) and [RLS advisory guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

## Scope and limits

This completes database corrections only. B4 application screens and adapter/read-save integration remain to be implemented. No UI build was needed for this database-only change. Multi-session concurrency stress testing was not performed.

## Application integration completed — 17 September 2026

The B4 route is `/carrier/[iata]/baggage-weights`, linked from B3. It includes default per-piece weights, protected All Flights baseline and class/category/variation records, and planning assumptions. It uses the shared workspace branding, blue focus styles and shaded section headings. Paragraphs use the available section width and wrap naturally on narrow screens.

Domain validation, application authentication/carrier checks, repository port and request-scoped Supabase adapter are separate. Only the infrastructure adapter calls Supabase. No additional schema changes or service-role credentials were needed.

Each Save or Remove operates on one record. The adapter checks a snapshot revision, then updates/deletes with all original stored fields as predicates in the same statement, rejecting concurrent edits to that record. Database constraints and RLS remain authoritative. This does not provide a transaction across multiple records or lock a concurrently changing B1 unit; multi-session unit-change stress testing remains outside these checks.

Verification:
- 64 automated tests passed, including baseline identity, invalid weights, duplicate scopes, unknown class/variation, decimal precision, administrator gating and stale revisions.
- Full lint, TypeScript and production build passed.
- Live signed-in browser saved the original per-piece values unchanged.
- Temporary First Class baggage values (15 per piece / 20 per passenger) saved and loaded after refresh.
- Temporary planning averages (1.25 bags, 18.75 weight, 0.045 volume) saved and survived reload; database confirmed exact four-decimal storage.
- Negative weight validation and Cancel were checked in the browser.
- A concurrent change to the temporary planning record produced the expected stale-edit warning instead of an overwrite.
- Desktop 1280px and mobile 390px reviewed. Mobile document width matched viewport width, with no horizontal overflow. Temporary viewport override reset.
- Temporary records removed under the authenticated administrator role. Final state: no ZZ planning rows; one protected baggage baseline remains UNSET; original per-piece weights retained.
- Full rollback-only B4 database permission/validation suite passed again. Security-advisor findings unchanged, with no B4-specific findings.

Browser removal of a saved record was not exercised; authenticated database removal and application removal guards were checked. Preview running at http://127.0.0.1:3006/carrier/ZZ/baggage-weights.

## Next work: B1 densities

User identified missing density settings under 1. STANDARD UNITS AND CODES. Review AHM565 B1 and the existing database density columns/units, then implement authorised administrator editing, validation and read-only access. Confirm downstream volume calculation semantics before treating blank B4 Average Bag Volume as an active density fallback. B4 now displays the requested intended fallback rule with an explicit pending-configuration notice. No density values or calculations have been invented. Any required schema changes remain subject to explicit approval.
