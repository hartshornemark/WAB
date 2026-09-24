# Commodity editor verification — 16 September 2026

Applied `commodity-codes.sql` to project ffmadtrcirrzywdqahbu with explicit user approval. Existing master rows were unchanged. The carrier table remains protected by RLS; both exposed functions run as SECURITY INVOKER. Existing administrator permission CARRIER_DETAILS_EDIT is reused.

- Lint, TypeScript, production build and all 37 automated tests passed.
- `commodity-role-checks.sql` passed against the live database, with all fixtures and writes rolled back: SA and CA save, master defaults, full replacement, duplicate/empty validation, stale revision rejection, Configuration Editor read-only, direct write rejection, cross-carrier insert/reassignment rejection, unassigned user denial and anonymous denial.
- Browser at port 3006: seven master defaults shown on B1; Edit and Cancel verified; duplicate rejected; full list saved through the server action and persisted after reload.
- Temporary browser test rows were removed with an exact full-set comparison guard. ZZ is restored to its original empty carrier-code set. Master defaults await the user's review and save.
- Security advisor: no new findings for these objects. Existing 11 INFO default-deny internal/legacy tables and existing disabled leaked-password protection warning remain.

The master table supplies initial suggestions only. Saving a carrier's codes never changes the master table, and later master changes do not overwrite an existing carrier set. The editor accepts 1–200 distinct codes, each 1–2 alphanumeric characters, and nonblank descriptions up to 64 characters.
