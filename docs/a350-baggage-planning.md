# A350 baggage planning contract

This correction is scoped to passenger aircraft type **359**. It does not enable
another aircraft's compact board or change the accepted A350 board geometry,
doors, drag/drop targets, or placement solver. Database changes require explicit
deployment approval. Reading a flight must never save or replace its baggage or
load plan.

## Separate the four stages

| Stage | Meaning | Authority |
| --- | --- | --- |
| Forecast | Expected bags, net weight and volume by passenger class/category | Booked passengers and applicable carrier planning assumptions |
| Proposed accommodation | Suggested physical ULD quantities and category contents, plus any Bulk remainder | Default Baggage ULD, its limits and compatible D3 capacity |
| Saved baggage accommodation | Operator-confirmed ULD/Bulk split and per-load category contents | Versioned `Operational_Baggage_Accommodation` record |
| Flight load plan | Actual placement of the released freight and baggage loads | AUTOLOAD/manual placement, independent validation and the flight's separate approval workflow |

The database status `ACCEPTED` on baggage accommodation means accepted **for load
planning**. It does not mean the flight load plan has been accepted or finalised.
An AUTOLOAD result or saved edition also does not constitute the user's approval.
Final traffic/close-out can supersede forecast contents through its existing
workflow; this correction does not change that process.

## Forecast and contents

1. Use the existing carrier assumption selection and flight variation. Keep BF,
   BJ, BP and BY identities, pieces and net weights throughout packing. Do not
   derive a new bag count from baggage weight or fabricate a ULD serial.
2. Use the configured **Default Baggage ULD**, not the general cargo ULD default,
   most numerous pallet option, or an invented aircraft default.
3. BF and BJ share one proposed ULD when their **complete combined contents** fit
   all three constraints: configured piece limit; baggage net weight plus one
   ULD tare no greater than maximum gross weight; forecast volume no greater
   than ULD volume. Equality is permitted. This rule was requested on 2026-10-23.
4. If that combined BF/BJ load does not fit, propose separate category loads,
   splitting each as needed to respect all three limits. BP and BY retain
   separate-category default proposals. An operator may explicitly change the
   piece distribution; mixed loads retain the full category breakdown.
5. Volume is a **forecast**, not a measured packed volume. Use each class's
   existing planned volume divided by its forecast pieces for a manual split.
   Missing active-class volume, weight or piece assumptions are a configuration
   problem, not permission to pack without a volume limit. The current validated
   A350 path requires KG/M3 settings; other units are reported for configuration
   review rather than guessed.
6. Preserve every category's pieces and net weight, including integer weight
   rounding. A shared ULD carries one tare, not one tare per baggage category.
   Do not accept empty proposed ULD rows, unidentified categories, a different
   ULD code, excess pieces, excess gross weight, or excess forecast volume.

## Shared physical space

1. D3 rows describe **alternative footprints**. AKE, PKC, LD8, PAG and PMC options
   must never be added as independent physical capacity. An unused possible
   pallet footprint does not exclude a baggage container.
2. Count baggage container capacity by finding a maximum-cardinality set of
   non-overlapping default-container footprints in the saved configuration.
   Atomic resources are scoped by hold. This also accounts for overlapping AKE
   options in the FWD hold. Missing occupancy mappings or ambiguous configuration
   choices stop the proposal with an explanatory note.
3. The selected compatible set is a **capacity witness**, not a set of baggage
   assignments or locks. AUTOLOAD remains responsible for actual positions and
   validates overlap, hold/compartment limits, weight, balance, and other loading
   constraints. A capacity estimate alone is not loading clearance.
4. Reserve forecast baggage ULDs before calculating a cargo offer. Once valid
   baggage accommodation is saved, reserve **that saved count and Bulk contents**
   instead, even if the operator deliberately chose a different count. Reserve
   baggage ULD tare in remaining payload exactly once.
5. Cargo capacity is **pallet first**. After preserving the baggage reservation,
   choose the largest mutually compatible arrangement of the configured LD7 cargo
   pallet. Prefer the configured cargo-default pallet, otherwise the first saved
   pallet code. Among equal pallet counts, retain the most compatible default
   container positions; then prefer higher pallet net capacity. Fill those
   residual container positions after the baggage reservation. Count each physical
   bay only once across pallets and all containers. PAG and PMC alternative rows
   must never be summed as simultaneously available positions.
6. Return the selected pallet and residual container quantities together in the
   cargo offer. The physical footprint witness includes the baggage reservation,
   but does not lock or assign any load. The placement solver still checks actual
   cargo, hold limits, unloading and balance. Missing pallet mappings or limits
   produce an explicit configuration message rather than invented capacity.

## Bulk, review and acceptance

1. Baggage that cannot be accommodated by the selected ULD allocation remains
   identified as Bulk by category. Bulk is permitted only where actual configured
   Bulk capacity exists, and both weight and forecast volume must fit.
2. Reserve that Bulk weight/volume before estimating remaining Bulk cargo
   capacity. An intentional all-Bulk override on a mixed aircraft is allowed only
   when it reconciles the forecast and fits the real Bulk hold.
3. Validate manual accommodation on the server as well as the form. Retain the
   existing permission checks, optimistic version check, unique load references,
   per-category reconciliation, and save workflow.
4. A valid saved allocation is not automatically replaced when this correction is
   installed. Show a saved/proposed count difference for review. A changed forecast
   or configuration that invalidates saved contents must flag review, withhold a
   ready cargo offer, and block AUTOLOAD until explicitly corrected. The correction
   must remain saveable; a stale saved record must not prevent its replacement
   through the normal operator action.
5. The Traffic Plan summary must show the actual saved/proposed ULD contents and
   Bulk pieces. Do not show a hard-coded `BULK (0)` or substitute the new proposal
   count for a saved zero-ULD allocation.

## ZZ9350 example and verification

The inspected forecast is 143 bags / 2,145 kg. The saved default is AKE, with a
50-piece planning limit, 100 kg tare, 1,588 kg maximum gross and 4.3 m3 volume.
With sufficient compatible space, the corrected default proposal is:

| Proposed ULD | Category contents | Bags | Net kg | Gross kg |
| --- | --- | ---: | ---: | ---: |
| 1 | BF 2 + BJ 4 | 6 | 90 | 190 |
| 2 | BP | 17 | 255 | 355 |
| 3 | BY | 50 | 750 | 850 |
| 4 | BY | 50 | 750 | 850 |
| 5 | BY | 20 | 300 | 400 |
| Total | All categories retained | 143 | 2,145 | 2,645 |

These are proposed load references, not invented ULD serials or fixed positions.
Each load must also pass its forecast-volume check.

The captured A350 D3 data contains 38 AKE candidate rows but supports 34 mutually
compatible AKE footprints. These are test-fixture findings, never hard-coded
production counts. With the five-ULD baggage proposal, the pallet-first reference arrangement
contains seven PAG pallets and eight compatible AKE positions: five reserved for
baggage and three remaining for cargo. Its cargo offer is **7 PAG + 3 AKE**. A saved all-Bulk allocation remains a
separate, explicit choice and is not silently converted by the correction.

`tests/a350-baggage-planning.test.ts` executes the real SQL migration and existing
save validation in isolated PostgreSQL (PGlite), reproduces the original zero-ULD
failure, and verifies overlaps, BF/BJ boundaries, piece/weight/volume limits, Bulk,
saved-state preservation, stale-plan correction, pallet priority and baggage reservations, permissions and unchanged
non-A350 behavior. The compatible-set algorithm is also checked against exhaustive
enumeration. Domain tests ensure invalid saved baggage blocks AUTOLOAD without
changing the placement algorithm.

## Baseline checkpoint — 2026-10-23

This baseline preserves the accepted A350 compact board, tray and Traffic Plan
presentation before any solver-capacity replacement work. It is not a release
approval or a claim that the current cargo-offer calculation is production-ready.

Known issue: ZZ9350 on 2026-10-24 has released freight and five accepted baggage
ULDs, but initial Load Plan loading fails. Database logs show statement timeouts
inside `private.a350_pallet_first_capacity`, called by
`get_operational_freight_planning`. Board initialisation reloads that planning
data, so the timeout prevents the compact board and tray from being displayed.
The UI currently reports only a generic Load Control failure. No correction for
this issue is included in the baseline. Future work must retain baggage
reservations and pallet-first priorities and keep board availability independent
of cargo-capacity calculation.

The migrations dated `20261022163520`, `20261022163956` and `20261022165656`
were already applied to the shared Supabase project with user approval. Their
inclusion here records the applied changes; establishing this Git baseline must
not execute them again.

At checkpoint inspection, local work was based on `2da97c1`. GitHub staging had
advanced to `bdcf60c` ("Fix provisional ULD dashboard reads"). That upstream
change remains separate from this checkpoint and must be reconciled before
starting the solver replacement. No merge or deployment is authorised by this
baseline checkpoint.
