# Version-2 passenger scenario handoff

Input preparation for Step 3 only. No capacity search, scenario comparison or
timing benchmark has been run on these seven packages. No operational data,
accepted plan, UI, AUTOLOAD or shared database function has changed.

## Preserved scenarios and sourced additions

The six user passenger mixes and explicit infeasible seventh case are copied
from the immutable `../passenger-scenarios` pack. Its class forecasts, packing
targets, four-class inconsistency and synthetic seven-bags-per-passenger stress
override are retained. The original files and checksums are not regenerated.

Read-only database captures in `source.json` and `verification-source.json` add
the missing V2 fields. Their queries are included. The manifest records timestamps
and provenance. This is an explicit enrichment of the older snapshot, not a claim
that the captures came from one historical transaction. The newer flight is
version 4, assigned ZZLGC; the original smaller flight capture was version 3.
Preparation verifies that aircraft identity, all 50 position rows and occupancy,
hold rows, selected ULD specifications and master volumes remain unchanged.

- MZFW: 195,700 kg from the applicable generic ALL/subtype limiting-weight row.
  The aircraft master value agrees; no fuel-configuration overrides are present.
- Effective DOW: assigned ZZLGC 136,804 kg, plus crew A and pantry A adjustments
  of zero. Repeated crew location rows do not multiply a code adjustment.
- Passenger planning: STANDARD, 84 kg per booked passenger from the carrier's
  Adult planning average, already including hand baggage. No class-specific
  weight rows or demographic mix are supplied. This matches the saved booking
  calculation's adult planning basis.
- ULDs: AKE tare 100 kg, PAG tare 110 kg. Gross limits use the smaller of ULD and
  position maxima (AKE positions are 1,587 kg, despite the 1,588 kg ULD maximum).
  Volumes use the applicable position limit or captured ULD master volume.
- Each ULD position belongs to its saved compartment, then saved hold. Their
  separate gross limits remain constraints. No additional shared hold is invented.
- Bulk: ALB compartment 5 contains saved areas 51 (1,841 kg / 11 m3),
  52 (667 kg / 4 m3), 53 (272 kg / 2 m3). Both compartment and hold cap the
  combined result at 2,780 kg / 17 m3. Cargo density is 212 kg/m3.

All seven frozen packing proposals reserve their requested baggage in AKEs,
with no Bulk diversion. Baggage ULDs carry their actual forecast net weight and
space, plus tare when placed. Ordered class contents follow the frozen piece
targets; BF/BJ may share the same target. Every case has 15 kg per bag, including
the stress override. Class forecast volume is apportioned across the bags in
each target. Largest fractional remainders receive residual millilitres, preserving
the exact sum of the frozen class volumes. The frozen four-decimal class sums
are used directly rather than silently recalculating their rounding.

These are synthetic cargo-offer scenarios, **not a replay of all existing flight
loads**. `fixedLoads: []` explicitly means no Bulk baggage or other fixed load
is reserved in these cases; existing released freight and accepted flight baggage
are not added on top of the synthetic proposal. Bulk reservation deductions are
covered by the separate rule unit cases. Case 07 retains all 42 requested AKEs;
it is not clamped or diverted to Bulk to make it fit.

## Identical component handoff and verification

For each case, `databaseInput` and `solverInput` in `manifest.json` point to the
**same JSON file**, with the same SHA-256 and content revision. Weights are
integer grams and volumes integer millilitres. The shared V2 input validator
checks every package. Neither capacity component is invoked by preparation.
Equal V1 reservation counts do not imply equal V2 inputs: cases 01 and 06 now
also carry their different passenger and actual baggage weights/volumes.

From the repository root, using the configured Node runtime:

```sh
node --import tsx tests/fixtures/cargo-capacity/passenger-scenarios-v2/prepare.mjs --check
```

`--check` reproduces the packages in memory and compares every saved byte and
checksum, without writing or solving. Initial generation uses the same command
without `--check`; do not regenerate this sealed pack when live data changes.
Create a separately versioned pack instead. The manifest also hashes all
referenced original source files.

The two-second prototype time limit is recorded, not accepted as a future
comparison/benchmark budget. A revised limit must produce the same new revision
for both components. The exhaustive offline SQL reference is a small-case
correctness oracle; it may be impractical for the full 50-position cases.
Preparing these inputs does not establish that it can finish those cases or
make its timing representative of the legacy database implementation. Resolve
that execution approach explicitly in Step 3, recording timeouts honestly.

These input packages make no claim about feasibility, optimum or performance
apart from the deliberately impossible reservation count in case 07.
