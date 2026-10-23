# Offline A350 database reference: exact group-frontier search

Status: preparation steps 1–5 and **Step 6 are complete locally**. Both
implementations proved equivalent results on all seven frozen scenarios; see
`solver/verification/a350-v2-seven-scenarios-2026-10-23/README.md` for the sealed
results, earlier inconclusive attempts, limits and exact code snapshots.
No performance benchmark, shared database change, application activation,
AUTOLOAD change, push, merge or deployment is part of this work.

## Installation and boundary

In an isolated PostgreSQL/PGlite database, load these files in order:

1. `solver/reference/max_net_cargo_v2.sql`: original exhaustive arrangement oracle,
   now named `capacity_reference.exhaustive_net_cargo_v2`, plus the existing
   independent arrangement evaluator and integral max-flow reconstruction.
2. `solver/reference/frontier_net_cargo_v2.sql`: exact group-frontier search,
   exposed through `capacity_reference.max_net_cargo_v2`.

Validate the complete V2 input with the existing domain validator first. The
optimized decomposition additionally requires each physical bay to belong to
one group across all candidate alternatives. Cross-group ownership is a clear
configuration error; it is never silently split. This condition is checked
against the sealed A350 inputs by static inspection only, without solving them.
All groups still come from the input hierarchy. The final aircraft merge is a
calculation boundary implementing MZFW/DOW/passenger allowance, not an invented
physical hold.

## The five preparation steps

### 1. Reject obvious impossibilities

Before constructing group frontiers, reject:

- More baggage ULDs than candidate container positions.
- A baggage ULD with no unblocked compatible position satisfying its actual
  weight plus position tare and volume.
- Fixed gross plus baggage net and minimum compatible baggage tare exceeding
  the aircraft allowance. Independent minimum tares are a lower bound only;
  this check cannot incorrectly reject a feasible joint placement.
- Fixed Bulk weight or space exceeding its saved area's limit.

Group-level fixed weight and shared Bulk-space violations also terminate the
relevant subtree before position expansion. These are necessary checks, not a
claim that every remaining input is feasible. The subsequent exact search still
checks overlaps, competition for positions and all shared limits.

### 2. Calculate local valid alternatives

Each group's candidates are processed in a deterministic physical-bay order.
Every candidate branches to unused, cargo or a specific compatible baggage ULD.
Fixed occupied bays are blocked throughout. A used bay remains in the state
until no remaining candidate in that group can claim it; only then is it
forgotten. This preserves long/multi-bay overlapping alternatives.

State witnesses retain exact baggage ID-to-position mappings and selected cargo
position IDs. Baggage identities are not replaced with a count, even when their
weights happen to match.

### 3. Retain only useful alternatives

A state contains:

- Exact assigned baggage-ID set and still-live occupied physical bays.
- Reserved gross `R`: fixed gross, actual baggage gross and selected cargo tare.
- Three integer net-weight bounds `U`, `B`, `T`: ULD-only capacity, Bulk-only
  capacity, and their combined maximum.
- A representative arrangement for later reconstruction.

The capacity region is `0 <= u <= U`, `0 <= b <= B`, `u+b <= T`.
Equal state summaries retain one witness. For **identical baggage sets and live
bays**, state A dominates B only if A has no greater reserved gross and no smaller
U, B or T. This deliberately retains trade-offs between tare, ULD capacity and
Bulk capacity. It does not select pallets or prune by pallet/container count.

A checked skyline accelerates dominance where each region has
`T=min(U+B,K-R)` within a fixed baggage/live-bay/Bulk-bound partition. With B
fixed, a lower R and no smaller U implies no smaller T; sorted prefix maxima
therefore remove only dominated states. The shape is checked for every input
state. If it does not hold, the general three-bound dominance test remains in
use, including for shared child limits.

Only baggage with identical net weight, volume and complete compatible-position
sets is interchangeable. Such loads use a canonical ID prefix during local
search. When children combine, right-hand IDs are rebound to unused original
IDs in that same equivalence class, preserving exact identity-to-position
witnesses. Loads differing in any requirement cannot be interchanged. This
removes permutation duplicates without replacing heterogeneous baggage with a
count or changing any reservation.

Hierarchy merging computes feasible baggage-mask combinations once per mask
pair, combines capacity summaries in a set-based query, and removes exact
duplicate summaries before reconstructing baggage mappings. No alternatives are
truncated. Explicit pair/state guards bound working-set growth.

### 4. Combine through the saved hierarchy

Child states may combine only when their assigned baggage sets are disjoint
after any fully interchangeable-ID rebinding described above. Add reserved gross and three capacity bounds, then apply the node's
configured gross limit and residual Bulk-volume limit. For residual gross `W`
and residual Bulk capacity `V` in grams:

```
T' = min(T, W)
U' = min(U, T')
B' = min(B, T', V)    # omit V only for an explicit null aggregate volume limit
T' = min(T', U'+B')
```

All fixed Bulk volume in the subtree is deducted before converting remaining
space to integer grams using the common configured cargo density. Area limits
are applied before parent limits; each child region already contains its own
weight/space constraints. Fixed gross is charged once per ancestor, not once
per alternative. At the aircraft merge, residual gross is
`MZFW - effective DOW - passenger weight - reserved gross`.

Only final states assigning every baggage ULD are eligible. Choose the greatest
T and reconstruct the actual per-position/per-area net weights with integral
max flow. The reconstructed net must equal the selected summary T; otherwise
raise an error rather than report an optimum. Zero-net cargo ULDs are omitted
from the returned witness and their tare is not reported as carried cargo tare.

### 5. Exactness argument and checks

**Local completeness:** every physically compatible unused/cargo/baggage choice
is generated. Forgetting a bay cannot affect any future choice, because the
algorithm first verifies that no unprocessed candidate references it. Removing
a state with a dominating summary preserves a continuation at least as good,
with the same baggage obligations and future footprint conflicts.

**Capacity representation:** for a fixed arrangement, both cargo categories are
divisible in integer grams. Individual sources and shared group gross limits
are capacity constraints; Bulk alone additionally traverses area and ancestor
space limits. With one common cargo density, this is a two-category integral
flow region. Its three nonempty-category bounds are U, B and T. Combining
independent children adds these bounds; clipping shared gross and Bulk-space
constraints gives the formulas above. Thus every retained summary represents
its complete attainable region, rather than just its largest local offer. This
is why a parent's Bulk-space constraint cannot make an incorrectly discarded
ULD/Bulk trade-off necessary later.

**Hierarchy induction:** the local region and baggage witness are complete at
leaves. Disjoint baggage merging, exact region addition, limit clipping and
safe dominance preserve completeness at every parent. Applying the aircraft
allowance and requiring all baggage gives the global maximum. Allowing zero
flow through a selected cargo ULD cannot increase the real optimum: dropping
that empty ULD only frees tare and physical space, and the unused branch is
also represented. Reconstruction omits such empty ULDs.

**Executable checks:**

- The 16 existing expected-answer rule cases still pass the new entry point.
- 88 small cases (16 known plus 72 deterministic generated layouts) compare
  feasibility and maximum net directly with the original exhaustive oracle.
- 20 further tiny layouts compare against direct enumeration of every integer
  cargo weight, using the domain validator for feasibility. This third oracle
  shares neither frontier summaries nor the SQL max-flow evaluator.
- A synthetic four-compartment case checks an independently derived optimum
  under a shared hold/aircraft limit and after reversing input order.
- A long-footprint case checks that a bay is not forgotten before its last
  alternative, and agrees with exhaustive search.
- Guard tests check immediate count rejection, identity/ULD/Bulk-safe dominance,
  cross-group bay errors and explicit state-budget failure.
- Eight additional baggage variants compare against exhaustive search, including
  identical loads with reordered compatibility sets, different weight, different
  volume and restricted compatibility. A non-simple shared-capacity region
  explicitly exercises the general dominance fallback.
- Every returned SQL witness is checked by the existing independent TypeScript
  validator, covering baggage fit, tare, overlaps, fixed reservations and every
  area/group/aircraft constraint.

Tests support the exactness argument within the explicit V2 model and ownership
condition; they do not establish operational correctness of unverified source
configuration or successful turnaround on the full seven scenarios.

## Limits and next authorised action

The retained/expanded working-state budget defaults to 20,000 per reduction,
with an explicit optional limit for the offline harness. Hierarchy combination
also has a 4,000,000-pair working-set guard. Exceeding either raises
SQLSTATE `54000`: no optimum established. There is no best-effort `OPTIMAL` or
false `INFEASIBLE`. The subsequent comparison harness must additionally enforce
a statement timeout and classify timeout/resource errors as inconclusive.
The input's Python solve limit does not itself cancel a PostgreSQL statement.

The frozen inputs remain sealed and unchanged. Step 6 has now resolved all
seven: cases 1–6 have equal proven maxima and independently validated witnesses;
case 7 is proven infeasible by both engines and the independent candidate-count
bound. The report retains original input hashes and the explicitly derived
10-second execution inputs supplied identically to both engines. Earlier
inconclusive attempts remain recorded as such. This is correctness verification,
not a measured performance benchmark or an operational rollout.

This optimized offline reference remains separate from the live legacy database
algorithm. Neither its old nor its new timings may be substituted for measured
legacy turnaround when claiming a speed improvement.
