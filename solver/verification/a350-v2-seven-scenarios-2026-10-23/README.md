# Step 3 — equivalent results verified

**Completed:** Step 6, run the seven scenarios. All seven are resolved; there are
no remaining inconclusive or mismatched cases in the final run.

| Case | Passengers F / C / W / Y | Baggage AKEs | Maximum net cargo, both engines | Cargo pallets / containers, both engines | Outcome |
| --- | --- | ---: | ---: | ---: | --- |
| case-01 | 3 / 10 / 22 / 230 | 7 | 31,201 kg | 6 / 1 | Both OPTIMAL; valid |
| case-02 | 9 / 25 / 4 / 150 | 5 | 38,714 kg | 7 / 3 | Both OPTIMAL; valid |
| case-03 | 10 / 25 / 30 / 100 | 4 | 40,701 kg | 6 / 8 | Both OPTIMAL; valid |
| case-04 | 7 / 4 / 0 / 75 | 3 | 47,555 kg | 3 / 21 | Both OPTIMAL; valid |
| case-05 | 0 / 0 / 30 / 30 | 2 | 49,936 kg | 2 / 26 | Both OPTIMAL; valid |
| case-06 | 14 / 38 / 15 / 200 | 7 | 31,003 kg | 6 / 1 | Both OPTIMAL; valid |
| case-07-infeasible | 0 / 0 / 0 / 297 | 42 | — | — | Both INFEASIBLE |

Maximum net cargo includes ULD cargo plus remaining Bulk cargo, after baggage,
tare, individual/shared hold limits and the aircraft allowance. Pallet/container
counts are recorded for completeness; equality of these counts was not required
for equivalence. They happen to agree in this final run. Actual position choices
may differ. Full per-position ULD, baggage and Bulk witnesses are retained in
`final/results.json` and the individual case result files.

## Verification evidence

- Both implementations received the same byte-identical JSON input per case.
  Original source hashes, execution input hashes, revisions and baggage/fixed
  reservation hashes are recorded. The archived execution inputs are in
  `final/inputs`. The frozen V2 pack and earlier source packs remain unchanged.
- Cases 1–6: both returned OPTIMAL with identical maximum permissible net cargo.
  Every returned witness passed the independent TypeScript validator for baggage
  identity/fit, footprint exclusivity, tare/totals, fixed reservations, Bulk
  weight/space/density, parent limits and aircraft weight allowance.
- Case 7: both returned INFEASIBLE. Its unchanged 42 requested baggage ULDs exceed
  even the 38 candidate container rows, independently establishing impossibility.
  No baggage was dropped, clamped or diverted to Bulk to make the case fit.
- These are the frozen synthetic planning scenarios, not changes to the live
  flight or its accepted load. Their known four-class configuration inconsistency
  remains deliberately deferred. No existing flight freight is added as a fixed
  reservation beyond the explicit scenario definition.

## Attempts and execution limits

The first pass used the original two-second solver inputs, a ten-second database
statement timeout and hard process deadlines of four and fifteen seconds.
Cases 4, 5 and 7 resolved. Cases 1, 2 and 6 hit the database hard deadline;
case 3 also had a FEASIBLE (unproved) solver result. These remain honestly
recorded as inconclusive in `initial/results.json`; they were not converted into
successful results. The initial database source is archived alongside them.

Longer exploratory retries still exposed excessive database work. The reference
was refined without changing calculation rules: only fully interchangeable
baggage is canonicalised; a checked exact skyline accelerates dominance; and
hierarchy combinations are deduplicated in a set-based query before reconstructing
witnesses. Exhaustive small-case comparisons, direct integer-weight enumeration,
heterogeneous baggage checks and the general-dominance fallback all pass.

The final complete seven-case run used:

- Solver: 10-second search limit, 12-second hard process deadline.
- Database: 60-second statement timeout, 65-second hard process deadline;
  20,000 states per reduction and a 4,000,000-pair combination guard.
- The time-limit-only execution inputs have new revisions and hashes. Both
  components received those same derived files; the original frozen inputs
  were preserved. All weight, baggage, footprint and other calculation fields
  are unchanged. SQL's statement limit is explicit because the Python input's
  search-limit field does not itself cancel a database statement.

The final run metadata records UTC timestamps and runtime versions. Its Git
commit is the parent checkpoint over which the tested changes were being made;
**the precise tested code is identified by SHA-256 and archived in `code/`**.
The report does not imply that the parent commit alone contains those changes.
`SHA256SUMS` seals this evidence bundle.

## Reproduction and scope

From the repository root, with the configured Node/Python runtime:

```sh
node --import tsx solver/verify_cargo_capacity.mjs --run \
  --output /absolute/path/to/a-new-empty-attempt-directory \
  --python /absolute/path/to/python-with-ortools \
  --solver-seconds 10 --database-seconds 60
```

The runner refuses an existing output directory and refuses to write into the
frozen input pack. It installs the SQL reference into a new isolated PGlite
instance, never the shared database. It bounds each child process, preserves raw
results, checks revisions and validates witnesses. Timeout/resource failures
remain inconclusive. Input/result hashes and archived witnesses can be checked
without rerunning a capacity search.

This completes **correctness equivalence for the agreed V2 rules on these seven
cases**. It is not a performance benchmark, a claim of production turnaround or
a speed comparison against the live legacy database. The unequal engine limits
must not be used to claim a timing improvement. No shared database changes,
activation, deployment, merge or push were performed.
