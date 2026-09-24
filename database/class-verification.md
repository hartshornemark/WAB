# Class-code editor verification — 16 September 2026

Applied `class-codes.sql` to project ffmadtrcirrzywdqahbu after explicit user approval.

## Behaviour

- B1 includes CARRIER CLASS CODES above load commodity codes.
- Code, Priority and Name / Description are editable; add/remove/save/cancel supports one to four retained classes.
- Priorities are distinct integers 1–4. Removing a class does not renumber the others. The existing numbered database slots store the priorities; no duplicate priority columns were added.
- Master defaults appear only when no carrier row exists. Existing carrier-specific values, including ZZ's E / Premium Economy, are preserved.
- Codes must be one ASCII letter A–Z. Lowercase application input is converted to uppercase. Numbers, symbols and multicharacter inputs are rejected. Direct database writes are protected by letter-only CHECK constraints in both tables.
- Names permit 1–64 characters. The former carrier-side 20-character checks were replaced to match the master limit.
- Class 1 may be unused, but each populated slot requires both code and name, each code must be unique, and at least one class is required in a saved row.
- The master table is read-only through the application. Existing master values are unchanged.

## Security and tests

- Lint, TypeScript, production build and all 44 automated tests passed.
- `class-role-checks.sql` passed on the live database. All fixture data and mutations rolled back.
- Database tests cover direct master and all four carrier slot letter constraints, duplicate codes, unpaired fields, missing/duplicate/invalid priorities, 1–4 classes, retaining priority 4 alone, descriptions of 64 characters, priority swaps, initial defaults/insert, stale-save rejection, Solution Administrator and Carrier Administrator saving, Configuration Editor read-only, cross-carrier denial, identifier reassignment, unassigned users and anonymous access.
- The exposed read/save functions use SECURITY INVOKER. RLS remains authoritative; only the existing two administrator roles with CARRIER_DETAILS_EDIT can save. No security tables or privileged credentials are exposed.
- Browser checks: original ZZ classes displayed; number rejected; duplicate priority rejected; three rows removed in draft leaving Y at priority 4; priority/name/code changed and row added; Cancel restored the original values; original values saved successfully through the server action. Blue field focus verified visually. No test class values remain saved.
- Security advisor reported no new findings for the class objects. Existing 11 INFO notices concern default-deny internal/legacy tables; the existing leaked-password protection warning remains: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
