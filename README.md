# Carrier Configuration

Initial Next.js + TypeScript application with Supabase isolated behind infrastructure adapters.

## Status

Implemented: email/password sign-in, cookie-based authenticated session, authorised carrier discovery, selection, selected-carrier workspace, sign-out, loading/error/empty/access-denied states.

**The Data API schema blocker is resolved.** With explicit user approval on 15 September 2026, the exposed schemas were set to `public, graphql_public, Basic_Carrier_Record` using the documented `authenticator` role setting. No table, grant or RLS policy changed. The assigned account has now exercised carrier selection and the full logo lifecycle in the in-app browser.

## Run

Requires Node.js 22+ (24 recommended), pnpm 11.19.0.

```sh
pnpm install --frozen-lockfile
cp .env.example .env.local
# Set NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY to the project's publishable key.
pnpm dev
```

The supplied local working copy already has `.env.local` configured with the project URL and its publishable key. This file is ignored by Git. No service-role or secret key is used.

Open http://localhost:3000. Use an existing account assigned access by your administrator. This slice does not create accounts or change passwords.

## Architecture

```text
src/
  domain/                    Provider-independent Carrier/User types and errors
  ports/                     AuthService and CarrierRepository interfaces
  application/               Sign-in, session, carrier discovery/selection use cases
  infrastructure/supabase/   SSR client, refresh proxy, auth and carrier adapters
  composition/               Request-scoped dependency assembly
  app/                       Next.js routes and server actions
  components/                React presentation
  proxy.ts                   Next.js entry point delegating session refresh
```

Pages and server actions call application services through the composition root. Application code depends only on domain types and ports. Adapters implement the ports and translate provider responses to domain values. No provider objects or credentials are passed to client components.

The custom ESLint architecture rule rejects SDK imports outside infrastructure, disallowed cross-layer imports (including relative and dynamic imports), and direct `supabase.*` calls outside infrastructure. Regression tests verify those restrictions. `server-only` also prevents server composition/adapters from being bundled into client components.

## Data and security contract

- Carrier source: `Basic_Carrier_Record.MASTER_Carrier_Contact`.
- Selected columns: `Carrier_IATA`, `Carrier_Name`; mapped to `iata`, `name`.
- The live columns were inspected, not inferred. The minimal database types also describe carrier branding and its two application-facing functions.
- Queries use the signed-in user's cookie-backed client and publishable key. PostgreSQL RLS remains authoritative.
- Discovery uses the existing `perm_master_select` policy: global or carrier-specific `MASTER_DATA_VIEW` permission. No application-security tables are queried by the application.
- Carrier selection is URL context, not authorization. Every selected-carrier request performs a fresh RLS-filtered query. Missing and unauthorised carriers share the same response.
- Proxy calls `getClaims()` to refresh tokens and propagates cookies and SSR cache headers. Protected application operations call `getUser()` for current server-verified identity, including revocation checks.
- Authenticated content is dynamically rendered with no-store fetches and private/no-store responses. Do not override this with CDN caching or ISR.
- New client/adapters are created per request. No shared user session or cached carrier list.
- Sign-out uses the local session scope. Provider failures are not shown verbatim to users.
- The app deliberately requires a modern `sb_publishable_` key and rejects secret/service-role keys in configuration.

## Live API configuration

Project: `ffmadtrcirrzywdqahbu`.

Approved and applied on 15 September 2026:

```sql
ALTER ROLE authenticator SET pgrst.db_schemas = 'public, graphql_public, Basic_Carrier_Record';
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';
```

The dashboard required sign-in, so the connected database tool applied Supabase's documented role-level configuration. **This overrides the dashboard exposed-schema setting.** Future changes must update this list or reset the role setting after configuring the equivalent list in the dashboard. The previous role had no `pgrst.db_schemas` override.

Verified: the API now recognises `Basic_Carrier_Record`; an unauthenticated request returns HTTP 401 / 42501 (permission denied), rather than HTTP 406 / PGRST106 (unexposed schema). Anonymous access was not granted. Existing RLS and grants remain unchanged. `application_security` and `private` are not exposed.

Authentication regression checklist for future releases:

1. Sign in and see precisely the carriers granted by existing RLS.
2. Open a carrier, reload, and confirm the session persists.
3. Enter an unassigned carrier URL and confirm access is denied.
4. Confirm an account without carrier permissions sees the empty state.
5. Sign out and confirm protected routes redirect to sign-in.

Do not create views, functions, grants, policies, or schema migrations as a workaround without explicit approval.

## Verification

```sh
pnpm verify          # lint, typecheck, 23 unit/adapter/boundary/image tests, production build
pnpm exec playwright install chromium
pnpm test:browser
```

The authenticated browser test requires `E2E_EMAIL` and `E2E_PASSWORD` in the test process environment, plus the API configuration above. Use a designated existing test account with at least one assigned carrier; never commit its credentials.

Verified on 15 September 2026:

- Lint: passed, no warnings.
- Type checking: passed.
- Unit/adapter/architecture/image tests: 23 passed.
- Production build: passed; authenticated routes are dynamic.
- Live PostgreSQL query under the authenticated role with an unassigned identity: zero carrier rows.
- Live Data API query: schema now recognised; unauthenticated access denied (HTTP 401 / 42501).
- In-app browser: `/carriers` and `/carrier/ZZ` redirect a signed-out visitor to `/login`; desktop sign-in layout visually inspected.
- Standalone Playwright could not launch Chromium in this host sandbox (macOS process permission denial). Its suite is included for an unrestricted development/CI environment.
- Logo testing used the existing signed-in assigned account; it did not require collecting or entering its password.

## Documentation checked before implementation

- [Supabase changelog](https://supabase.com/changelog.md)
- [Current Next.js SSR client guidance](https://supabase.com/docs/guides/auth/server-side/creating-a-client)
- [SSR authentication and caching](https://supabase.com/docs/guides/auth/server-side/advanced-guide)
- [Node.js 20 support removal](https://supabase.com/changelog/45715-deprecation-notice-dropping-support-for-node-js-20)
- [Data API exposure changes](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
- [Next.js proxy convention](https://nextjs.org/docs/app/api-reference/file-conventions/proxy)

All dependencies are pinned and the pnpm lockfile is included. TypeScript 5.9 and ESLint 9 match the installed Next.js lint plugins' supported peer ranges; review those development-tool versions when upgrading the plugin stack.

## Carrier logo management — completed 15 September 2026

Open a carrier workspace and use **Company logo** to upload, replace or remove its logo. PNG, JPEG and WebP files up to 2 MB are accepted. The server decodes the file, limits input to 16 million pixels, preserves transparency, strips metadata and scales it within 1024 × 1024 before storing PNG. Invalid images and SVG are rejected.

Stored logos appear on carrier selection and in the workspace. Removing a logo explicitly restores the IATA fallback. The bundled ZZ image is used only when no branding row exists; an explicit removal suppresses it.

### Storage and authorization

- Private `carrier-logos` Storage bucket; `Basic_Carrier_Record.Carrier_Branding` contains the carrier's current file reference.
- `CARRIER_BRANDING_EDIT` is mapped to Solution Administrator and Carrier Administrator roles. Existing carrier visibility and permission scope are checked by PostgreSQL RLS for metadata and storage operations. Other users see the logo without editing controls.
- All operations use the signed-in user's SSR client. No service-role key or application-security table is exposed to presentation code.
- Display URLs expire after one hour. Reloading the page obtains a new URL after fresh authorization. An issued URL remains usable until expiry, so it must be treated as temporary bearer access.
- Replacement uploads a unique file, atomically swaps the reference, then removes the previous file. Removal clears the reference before file deletion. Concurrent reference changes are serialized per carrier.
- If cleanup fails, the UI reports that administrator cleanup is needed. An ambiguous reference-save failure can leave an unreferenced upload intentionally: deleting it immediately could break a save that actually committed. There is no automatic orphan-cleanup job. Administrators should reconcile references against aged bucket objects and delete only confirmed unreferenced files through the Storage API.
- `database/carrier-branding.sql` records the already-applied provisioning; it is not an idempotent migration and must not be blindly rerun.

### Final verification

- Lint, TypeScript, production build and all 23 automated tests passed.
- Live browser: uploaded ZZ logo, replaced it, removed it, verified the IATA fallback, then restored the supplied ZZ logo from private storage.
- Database checks: replacement retained exactly one current object; removal left a null reference and zero objects.
- Unassigned authenticated identity: zero visible branding rows and storage objects; both the save function and direct metadata mutation were denied.
- Anonymous identity: metadata read and save function denied.
- Security advisor reported no new logo-specific finding. Existing leaked-password protection is disabled; internal tables without RLS policies remain default-deny. Password protection was not changed as part of logo work.
- Native in-app browser testing was used because standalone Chromium is blocked by this host's process sandbox. Automated logic checks include unauthorized access, invalid files, image normalization, cleanup failures and replacement ordering; they do not substitute for a full multi-account browser role matrix.

## Master carrier identity

Carrier identity now reads IATA, name and ICAO exclusively from MASTER_Carrier_Contact through the carrier adapter. The workspace displays all three as read-only. Master create/edit remains governed by existing MASTER_DATA_CREATE/EDIT permissions, currently assigned only to Solution Administrator. A master-identity editing UI is not included in this change.

Basic_Carrier_Data retains compatibility copies of name and ICAO. Their fixed-width character types were changed to varchar to match the master without padding; the existing duplicate name was aligned to the master. A composite foreign key enforces the entire identity and cascades master name/ICAO updates atomically. An invoker insert trigger derives these fields from the visible master row. No privileged synchronization function or service-role client is used. Existing RLS is unchanged.

IATA updates on existing basic/contact records are rejected: changing a linked carrier identifier requires a coordinated administrator migration, not a normal field edit. Other tables' Carrier_IATA fields remain relational links under existing RLS and foreign keys.

Applied SQL is recorded in database/carrier-identity.sql (not idempotent). Verification: 23 tests, lint, typecheck and build passed. Rolled-back database tests proved conflicting identity edits fail, identifier edits fail, Solution Administrator master name/ICAO updates cascade, and unassigned identities update zero rows. Test identity changes were rolled back.

## Carrier Details — completed 16 September 2026

The workspace displays stored contact information and basic operating preferences. Edit details opens a form with Save changes and Cancel. Identity remains read-only and is read from the master. Existing company branding and the blue theme are retained.

`CARRIER_DETAILS_EDIT` is assigned only to Solution Administrator and Carrier Administrator. Configuration Editors retain their existing read access but cannot insert, update or delete contact/basic records, including through direct Data API calls. Carrier Administrators remain restricted to their assigned carriers. Solution Administrators can maintain details for visible master carriers. Other configuration tables keep their existing permissions.

The request-scoped adapter calls invoker functions `get_carrier_details` and `save_carrier_details`. The database enforces the same authorization as the form. Contact and basic records save atomically; identity fields cannot be submitted. New records inherit master identity. The save compares an opaque revision derived from both rows and their row versions after taking locks, rejecting stale forms. Direct external writers must implement their own concurrency handling.

Validation covers required address/city/country, field lengths, email syntax, seven-character optional teletype address, and exactly one supported selection per operating preference. Optional blank contact fields are stored as null. Existing stored values are displayed without inventing missing defaults. Revision conflicts preserve the user's draft and ask them to reload after copying any changes they wish to keep.

Verification: all 30 automated tests, lint, TypeScript and production build pass. Transaction-only database checks passed for administrator saves, carrier-scoped saves, Configuration Editor direct-write denial, unassigned/anonymous denial, first setup, inherited identity, invalid inputs, identity injection and stale-save rejection. All temporary role assignments and test records were rolled back. SQL implementation and repeatable role checks are under database/carrier-details*.sql; the implementation file is an applied change record, not an idempotent migration.

Live browser verification on 16 September 2026: the assigned administrator loaded the existing ZZ contact details and preferences, entered and cancelled a draft, received required-city and invalid-email messages, successfully saved the existing details, and reloaded to verify persistence. The W/B branding, blue theme and stored ZZ logo rendered correctly. The live save normalised trailing whitespace in the existing address; no business values were replaced with test values. Current preview: http://127.0.0.1:3005/carrier/ZZ. The old preview process on port 3004 could not be stopped within the host sandbox, so use port 3005 for this version.

The security advisor found no new feature-specific issue. The pre-existing disabled leaked-password protection warning remains; internal security tables without policies remain default-deny. Browser testing used the existing Solution Administrator session; other roles were tested with actual PostgreSQL policies in rolled-back transactions, rather than by leaving extra accounts or role assignments behind.

### Logo management update

Company logo display and controls are now embedded in Carrier Identity, alongside the centrally managed identity fields. CARRIER_BRANDING_EDIT is assigned only to Solution Administrator; can_manage_carrier_logo now requires that global permission, and no longer accepts carrier-scoped permission. Existing branding and Storage RLS policies use this helper, so upload, replacement and removal are restricted in the database as well as the UI. All 30 tests, lint, TypeScript and production build passed; a rollback-only permission check verified the Solution Administrator is allowed and the same identity without that role cannot call set_carrier_logo. Current preview uses port 3006.

### Signed-in display name

The shared workspace header prefers the account display name, falling back to email when absent or unavailable. The approved current_display_name lookup has no user-id argument and returns only auth.uid()'s active application-user name. A private, fixed-search-path function reads that single field; its exposed wrapper runs as invoker. Anonymous execution is revoked. Authorization never depends on the display name. Verified: Mark Hartshorne appears in the live header; another unassigned identity receives null and anonymous calls are denied. All 31 tests, lint, typecheck and build passed before applying the lookup. Security advisor findings remain unchanged.

### B4 — Standard Baggage Weights and Planning

Implemented `/carrier/[iata]/baggage-weights` and B3 Next navigation. Administrators can edit default per-piece weights, the fixed All Flights per-passenger baseline, class/category/flight-variation exceptions and decimal planning assumptions. Each record has Save/Cancel and eligible records have Remove. Existing RLS remains authoritative; no new database changes were required for the screens. Supabase operations remain in the infrastructure adapter.

Verification: 64 tests, lint, TypeScript and production build passed; live save/reload, validation, Cancel, stale-edit rejection and desktop/mobile layout checked. Temporary test records were removed. Full details and concurrency limitations: `database/baggage-b4-verification.md`. Current preview: http://127.0.0.1:3006/carrier/ZZ/baggage-weights.

### B1 Commodity Density Settings — completed

B1 now provides Checked Baggage, General Cargo and General Mail density editing for authorised administrators. Densities use the carrier's selected weight/volume units and convert atomically when those units change. The renamed density columns are connected through invoker functions and the infrastructure adapter. Existing values are preserved. See `database/density-settings-verification.md` for checks and limits.


## B5 ULD specifications

Implemented at `/carrier/[iata]/uld-specifications`, linked from B4. See [B5 verification](database/uld-b5-verification.md) and [database checks](database/uld-b5-checks.sql). Master values use KG/m³; carrier values use B1-selected units. Administrator-only saving and one default per adopted ULD type are enforced in PostgreSQL.
