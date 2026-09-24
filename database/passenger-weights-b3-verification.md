# B3 application verification — 17 September 2026

## Delivered
- /carrier/[iata]/passenger-weights, reached by Next on B2; back link to B2.
- 3.1 reads/saves existing Carrier_Passenger_Weights_ALLFLIGHTS values.
- Flight variation editor adopts master suggestions and manages custom carrier codes/descriptions.
- 3.2 creates, edits and removes class-specific standard/default or named-variation sets, with per-set remarks.
- Hand-baggage inclusion controls keep separate values inactive without erasing them.
- Shared brand and carrier logo, blue focus styling, strong section headings and full-width paragraph flow.
- Domain validation, application authorisation, repository port and Supabase-only infrastructure adapter.
- Applied approved passenger_weights_b3_api migration: invoker APIs, atomic section saves, stale-data/unit checks, updated ALLFLIGHTS permissions/constraints and variation label uniqueness.

## Evidence
- Lint, TypeScript and production build passed; 58 automated tests passed.
- passenger-weights-api-checks.sql passed live within a rolled-back transaction: default/class/variation round trips, stable IDs, invalid inputs, stale data and units, atomic failure, referenced variation removal, editor direct/RPC denials, carrier administrator save, cross-carrier and anonymous denial.
- Browser: navigated B2 to B3; loaded original default weights; excluded hand baggage without a value was rejected; saved original default weights successfully.
- Browser: adopted a master suggestion, changed it into a temporary test variation, saved; created a class-specific test set, saved and reloaded successfully.
- Browser: Cancel discarded an altered Male value and restored 93.
- Temporary browser rows were removed using exact predicates; final database read confirmed original ZZ default values, zero class weight rows and zero adopted variation rows.
- Desktop screenshot verified shared blue branding and logos; paragraph width 1048px with no max-width cap.
- 390px mobile preview verified natural paragraph wrapping and document width equal to viewport (no page overflow). Temporary viewport override reset.
- Security advisor retained the 11 existing default-deny informational notices and the existing leaked-password-protection warning; no new findings.
- Source search found no Supabase queries in presentation, application or domain layers.

## Scope
Actual hand-baggage mode is not included, as agreed for the initial standard-weight implementation. ALLFLIGHTS remains the single carrier default; variations are supported in class-specific weight sets. No automatic matching or precedence between overlapping flight labels is implied. Multi-session concurrency stress tests have not been run; database locks and stale-edit checks are implemented and stale revision/unit failures tested.
