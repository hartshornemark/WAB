# Frozen inputs: ZZ9350, 24 October 2026

Benchmark step 1 only. Captured from the shared database in a single SELECT
statement on 23 October 2026 at 11:09:54 Manila time. The database snapshot ID,
UTC timestamp, source project, record versions and file hashes are in
`manifest.json`. Source application commit: `d58e838`.

This case contains 138 booked passengers (F 3, C 7, W 19, Y 109), 138 forecast
bags / 2,070 kg net, and an accepted five-AKE baggage reservation. Its capacity
candidate set contains 12 PAG alternatives and 38 AKE alternatives. These are
candidate positions with overlapping physical resources, not simultaneous
capacity counts. No capacity result has been calculated for this frozen case.

## What is frozen

- `source.json`: passenger bookings, accepted baggage contents, flight/config
  identity and versions, ULD specifications, units, hold configuration/limits,
  relevant D3 position rows and hold-qualified occupancy mappings. It also records
  the live database function definitions for later comparison.
- `capture.sql`: the exact read-only source query. It selects the pallet and
  default baggage-container specifications and reconstructs the arguments to the
  existing capacity function without invoking the search or planning RPC.
- `database-arguments.json`: the three frozen arguments to
  `private.a350_pallet_first_capacity`: pallet candidates, container candidates
  and baggage ULD count.
- `solver-input.json`: the same IDs, physical resources, reservation and net
  limits in the existing prototype solver format. Net kg is converted to grams
  exactly, with no rounding. The input revision is the SHA-256 of the database
  argument file. The prototype's two-second execution setting is recorded but
  has not been exercised or adopted as a benchmark acceptance threshold.
- `manifest.json` and `SHA256SUMS`: provenance, counts and integrity checks.

The booked passengers explain the baggage reservation; they are not direct
inputs to the core cargo-capacity search. Baggage planning first produces a
proposal for user acceptance. The cargo-capacity search then reserves those
accepted baggage ULDs before determining cargo pallet/container capacity.

## Scope and stop point

The comparison boundary is the core footprint search, not a complete cargo-offer
RPC or browser request. Payload and Bulk post-processing, permissions, network
timing and UI rendering are outside this frozen core argument contract. Hold
limits and source metadata are retained as context; neither core implementation
receives additional constraints through this snapshot.

Existing candidate-selection semantics are captured as-is, including all rows
selected by the current database wrapper. They have not been corrected or
redesigned. The solver/database objective difference remains unresolved for
benchmark step 2. No equivalence search, performance measurement, database
correction, application activation, migration or deployment was performed.

For later comparison, both implementations must consume these committed files,
not re-read changing live data or reconstruct the previous October 22 fixture.
If a source input changes, create a separately versioned snapshot; do not update
this one in place. The old preliminary benchmark does not measure this new case.

Verify checksums without calling either calculation:

```sh
cd tests/fixtures/cargo-capacity/zz9350-2026-10-24
shasum -a 256 -c SHA256SUMS
```
