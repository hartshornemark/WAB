# A350 cargo-capacity calculation rules

Status: Step 2, local and inactive. Rules identifier: `A350_MAX_NET_CARGO_V2`.
Applies only to aircraft type 359. No shared database migration, application
activation, AUTOLOAD change, merge or deployment is included.

## Objective and calculation boundary

The objective is the greatest permissible **net cargo weight**, combining ULD
cargo and remaining Bulk capacity. Pallet count and container count are not
objectives. Container-only, pallet and mixed arrangements compete after all
constraints have been applied. Different arrangements with equal net offers are
equally valid; the old pallet-first and identity tie-breaks do not apply.

Passenger bookings first determine baggage pieces, forecast weight and volume,
and the proposed baggage ULD/Bulk reservation. That preparation precedes this
capacity search. Both calculation components must receive the same prepared
reservation and configuration snapshot; neither may silently repack baggage,
discard an impossible reservation, or move it to Bulk to manufacture feasibility.

For each compatible arrangement:

1. Reserve baggage ULD footprints and actual baggage net weight plus ULD tare.
   Charge fixed Bulk baggage and other reservations at their actual gross weights
   and volumes. Charge each reservation once.
2. Select non-overlapping cargo positions from configured alternatives. Atomic
   physical bay IDs are hold-qualified and shared by every alternative claiming
   the same space. An unused alternative contributes no capacity or tare.
3. Each cargo ULD contributes up to its configured maximum gross weight minus
   tare. The selected position identifies the applicable ULD/position capacity;
   the input producer must resolve restrictive aircraft and ULD limits first.
   ULD volume is also checked for baggage fit. This is a maximum weight offer,
   not a forecast of cargo commodities or a packing simulation.
4. Include all configured Bulk areas. Deduct fixed reservations from both area
   weight and space. Bulk cargo cannot exceed remaining weight or configured
   cargo density multiplied by remaining volume.
5. Apply every configured compartment/hold parent limit. Descendant gross loads
   count once at each ancestor; shared weight and Bulk-space limits cannot be
   multiplied by the number of child areas.
6. Apply the aircraft allowance, including selected cargo ULD tare:

   `cargo net <= MZFW - effective DOW - passenger weight - baggage gross
                 - other reserved gross - cargo ULD tare`

7. Maximise the combined permissible ULD and Bulk net weight **after** these
   constraints. A nominally larger arrangement may lose because of tare, a
   shared hold limit or the aircraft allowance.

Zero cargo is a valid feasible offer. Baggage or fixed reservations that cannot
fit produce `INFEASIBLE`, not a zero-capacity success.

## Explicit input contract

`src/domain/cargo-capacity.ts` defines the versioned input and independent result
validator. Weights are integer grams; volumes are integer millilitres; cargo
density is integer grams per cubic metre. Calculations retain exact integer or
rational precision, never round available space up. A Bulk allocation consumes
`net grams * 1,000,000 / density` millilitres. Shared volume checks use this
fraction directly, with a single configured cargo density across Bulk areas.

Inputs include MZFW, effective DOW, passenger weight, cargo density, the explicit
group hierarchy and limits, cargo alternatives with footprints and tare, Bulk
areas, individual baggage ULD requirements and fixed reservations. A fixed Bulk
load identifies exactly one area; its ancestors derive from that area. Other
fixed loads identify a group and explicit occupied bays. Empty arrays are
explicitly permitted when no such resources/reservations exist.

Missing limits, structure or location are configuration failures. An explicit
`null` group Bulk-volume limit means no additional aggregate Bulk-space limit;
individual area limits still apply. Applicable configuration must be sourced and
validated, rather than inferred from a drawing or an aircraft-wide ULD count.

## Local implementations and safety

- `solver/cargo_capacity.py` models the constraints in CP-SAT with one net-weight
  objective and a bounded solve deadline. The ordinary AUTOLOAD path is separate.
- The **offline database reference** is installed only in isolated PGlite.
  Load `solver/reference/max_net_cargo_v2.sql` (retained exhaustive oracle and
  integral-flow evaluator), then `solver/reference/frontier_net_cargo_v2.sql`
  (the optimized `max_net_cargo_v2` entry point). The new search rejects obvious
  impossibilities, reduces local alternatives exactly, and combines capacity
  regions through the saved hierarchy. See `docs/a350-capacity-reference-exactness.md`
  for the proof argument, tests, ownership guard and explicit state limit.
  Callers must validate inputs and enforce statement timeouts. Neither file
  is a migration; resource/timeout errors never establish an optimum.
- The TypeScript validator independently checks either implementation's complete
  witness, reservations, footprint exclusivity, tare, totals and all limits.
  Feasibility validation alone does not prove optimality.
- Results retain snapshot revision and explicit `OPTIMAL`, `FEASIBLE`,
  `INFEASIBLE` or `UNKNOWN` status. Only `OPTIMAL` establishes the maximum;
  `FEASIBLE` is an unproved lower bound. Unknown/infeasible results have no offer.
- The inactive process adapter bounds execution/output and concurrent workers.
  Snapshot freshness, deployment-wide admission and application integration
  remain requirements before activation.

## Verification and next boundary

Sixteen tiny synthetic rule examples exercise container/pallet winners, aircraft
allowance and tare, baggage fit, blocked footprints, nested/shared limits, Bulk
reservations, volume rounding and zero/infeasible offers. Both local
implementations are checked against their explicitly known expected answers;
returned witnesses are independently validated. These are rule unit tests, not
the seven frozen passenger-case comparisons or performance benchmarks.

The frozen version-1 flight inputs and passenger scenarios remain unchanged.
Their separately sourced version-2 enrichment is now sealed in
`tests/fixtures/cargo-capacity/passenger-scenarios-v2`. Its manifest identifies
the new capture timestamps, field provenance, explicit synthetic reservation
scope and identical input file for each component. Preparation checks original
aircraft/ULD/footprint data for drift and validates all seven packages without
running either capacity calculation. See that pack's README for reproduction
and the remaining comparison execution-budget decision. The optimized reference
preparation and seven-scenario equivalence verification are complete. The sealed
report is `solver/verification/a350-v2-seven-scenarios-2026-10-23/README.md`.

The live legacy database remains pallet-first and is **not aligned** by this
local change. Historical prototype timings use different rules and cannot
substantiate a like-for-like speed improvement for version 2. The seven frozen scenarios now pass correctness equivalence locally; timing
benchmarks, integration and live migration remain subsequent work.

The exhaustive offline SQL reference is a correctness oracle for small cases,
not a representative performance baseline for the existing database algorithm.
Its runtime must not be substituted for measured legacy database turnaround
when claiming an improvement. If old and new rules yield different offers,
report the semantic change separately from any measured runtime comparison.

## Subsequent repeated local measurements

The local calculation/request measurement stage is recorded in
`solver/benchmarks/a350-v2-local-request-2026-10-23/README.md`: 182 measured
requests plus 14 warm-ups, all correct and proven. It separates core calculation
from complete loopback HTTP requests and Python startup/transport. It shows a
scenario-dependent winner, not a universal solver speedup. Live legacy database,
hosted native PostgreSQL, remote-service and production-flight request timings
remain outside this result. No application activation or shared database change
was needed to obtain these local measurements.
