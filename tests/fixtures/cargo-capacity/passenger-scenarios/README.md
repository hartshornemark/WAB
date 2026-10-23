# Passenger-mix benchmark scenarios

These fixtures extend benchmark step 1. Cases 01–06 preserve the user's supplied
F/C/W/Y counts exactly. Case 07 is an agent-designed infeasible baggage-reservation
stress case, requested by the user. No live flight, accepted baggage plan, cabin
configuration or carrier planning assumption is changed.

All cases use the same immutable aircraft snapshot in `../zz9350-2026-10-24`.
The four-class inconsistency and case 06's C38 exceeding the selected cabin's
Business seats are intentionally retained by user instruction. These are
synthetic benchmark inputs, not operationally valid accepted passenger records.

## Shared baggage assumptions

Read-only carrier assumption capture: `baggage-assumptions.json` and its source
query `capture-baggage-assumptions.sql`. All four classes currently fall back to
the same carrier baseline: one bag and 15 kg net per passenger. Per-bag volume is
unset, so volume uses the captured checked-baggage density of 176 kg/m3 in
`baggage-density.json`. Aircraft limits come from the earlier aircraft snapshot:
AKE, 50 pieces, 100 kg tare, 1,588 kg maximum gross and 4.3 m3 volume.

`prepare.mjs` prepares these fixtures offline. It uses PostgreSQL numeric rounding
in in-memory PGlite, including the existing two-decimal aggregate volume and
four-decimal class allocation. It executes only the captured pure baggage
packing function, `private.a350_baggage_piece_targets`, to derive ULD piece
targets. It does not call either cargo-capacity calculation. BF/BJ share a ULD
only when their combined pieces, weight and volume fit, as in the current rules.

| Case | F | C | W | Y | Passengers/bags | Net kg | Requested AKE reservation |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 01 | 3 | 10 | 22 | 230 | 265 | 3,975 | 7 |
| 02 | 9 | 25 | 4 | 150 | 188 | 2,820 | 5 |
| 03 | 10 | 25 | 30 | 100 | 165 | 2,475 | 4 |
| 04 | 7 | 4 | 0 | 75 | 86 | 1,290 | 3 |
| 05 | 0 | 0 | 30 | 30 | 60 | 900 | 2 |
| 06 | 14 | 38 | 15 | 200 | 267 | 4,005 | 7 |

These are baggage packing requirements, not cargo-capacity results. There is no
Bulk diversion in these benchmark requests. Case 06 has 52 BF/BJ pieces, so those
two categories cannot share a single 50-piece AKE. Case 01 can share BF/BJ.
Both nevertheless reserve seven containers and have identical core search
inputs, recorded by `coreInputDuplicateOf`. They remain distinct baggage-planning
cases. The complete cargo offer may also differ because total baggage weight is
outside the core footprint-search contract.

## Explicit infeasible reservation

Case 07: F0/C0/W0/Y297 with a **synthetic seven-bags-per-passenger** assumption
and 105 kg baggage per passenger (15 kg per bag). This gives 2,079 bags / 31,185 kg
and 42 AKE packing targets. Requesting all 42 as reserved ULDs, with no Bulk
diversion or reservation clamping, exceeds even the 38 candidate container rows.
It therefore cannot fit, independently of overlap details. This is a deliberately
impossible reservation request, not a real baggage allowance, accepted plan or
an ordinary passenger-only variation under the baseline assumptions.

## Handoff and integrity

`passenger-cases.json` preserves the scenario definitions and explicit overrides.
`prepared-cases.json` records each class forecast, piece targets and reservation,
plus the exact database argument object and lossless solver input for that case.
`manifest.json` records sources, SHA-256 hashes and duplicate core inputs.
`SHA256SUMS` seals the case pack. No timing results are present because neither
capacity component has been executed on this pack.

The aircraft snapshot and baggage assumption/density captures have separate
timestamps, recorded explicitly; this pack does not claim a single live database
transaction across those captures. Both comparison components must use the
frozen files rather than mixing in later live reads.

The prototype's two-second search setting is retained in solver payloads; it is
not an agreed benchmark execution budget. The database/solver objective alignment
and timed comparison remain pending. Input preparation does not resolve them.

From this directory, verify the sealed files with `shasum -a 256 -c SHA256SUMS`.
To reproduce preparation in a disposable copy, run `node prepare.mjs` from the
repository's configured Node runtime. Do not regenerate this committed case pack
in place when live inputs change; create a separately versioned case pack.
