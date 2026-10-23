# A350 Load Plan hold board

## Accepted reference and change policy

The user accepted the A350 compact hold board as the reference on 2026-10-22.
Preserve its layout style. Further work is limited to bug fixes against the rules
in this document. Do not enable another aircraft type without the user's explicit
authorization for that individual type. Acceptance of the A350 does not authorize
rollout to other types, deployment, or merging.

This change is enabled only for aircraft type **359**. Other aircraft keep their
existing renderer. The implementation is shared and contains no A350 coordinates,
bay counts, position lists, or aircraft-specific CSS. It does not change D2/D3/D4,
solver constraints, saved plans, the separate aircraft outline viewer, or printing.

## Rendering rules

Baggage forecast, accommodation and shared-space capacity rules are documented in
[A350 baggage planning](a350-baggage-planning.md). They do not change this board's
rendering or placement rules.

1. Use the same fitted fuel configuration as AUTOLOAD. Read applicable holds and
   areas from D2, physical bay definitions from D3, and door anchors from D4.
2. Use existing D2 family identities to join FLF/FLA into FWD and ALF/ALA into AFT.
   Draw tail left, nose right: Bulk, AFT, FWD. Keep the saved hold IDs internally.
3. Within a hold, sort D3 bay ranges aft to forward. Identical longitudinal ranges
   share a column; L occupies the upper lane and R the lower lane. The board is a
   compact schematic of bay resources, with equal column widths; it is not a
   dimensioned airframe drawing. All holds stay on one line, with no forced
   minimum width or horizontal scroll at ordinary screen widths.
4. Keep every saved atomic bay visible. The available numbered positions are
   **alternatives**, not a count of independently usable positions. Do not remove,
   renumber, or claim simultaneous capacity for overlapping FWD options.
5. Draw combination outlines from the exact `SolverPosition.occupiedBayIds` used
   by AUTOLOAD. Side alternatives use neutral dotted outlines, full-width LD8
   arrangements use amber dots, and pallet footprints use blue dashes. Preserve
   different occupancy variants for the same position name (for example the PAG
   and PMC variants of 13P).
6. A drop or PLACE action passes only the exact solver IDs for that displayed
   target into the existing manual move/swap handler. That handler uses the same
   independent validator as AUTOLOAD. Selecting or moving a load never rebuilds
   the physical layout. A placed combination shades every claimed bay resource.
   Each assigned load displays its ULD/bulk identity or load reference, destination,
   and weight in kilograms. Combination footprints show that card once across the
   footprint; OCCUPIED is only a secondary resource state. Empty bays retain BAY.
7. Bulk areas remain separate targets from D2. Do not combine their capacities or
   invent missing physical boundaries. Door markers use saved D4 anchors and
   orientation. Each saved door has one marker outside the group frame: L on the
   upper edge, R on the lower edge. A centreline C door uses its anchored external
   end; if that end cannot be established, show a configuration note. AFT/ALA 43,
   BULK area 52, and FWD 12P are explicit saved anchors, not in-cell door labels.
   Missing or ambiguous door mappings produce a visible D4 configuration note
   while the rest of the board remains usable.
8. No bay lock states are available in the current D4 contract. Do not copy the
   reference image's example locks into operational data. Missing bays, invalid
   ranges, conflicting definitions, unplottable occupancy, or inaccessible
   configuration produce a clear configuration message instead of guessed boxes.

## A350 evidence and reference differences

The read-only configuration snapshot captured on 2026-10-22 has 38 D3 atomic bay
resources: eight aft pairs and eleven forward pairs. D2 has three bulk areas,
51/52/53. All 121 usable solver positions map to a visible target.

The first compact reference contains different example labels and lock/occupancy
states. The later airframe reference confirms aft pairs 45–41 and 33–31 and forward
pairs 26–21. It omits 13L/13R, which remain present as alternatives in saved D3.
The user clarified that FWD positions 11–15 cannot all be used together.

For example, saved AKE position 12L claims resources 12L and 13L. Position 13L
claims 12L/13L/14L, and position 14L claims 13L/14L. These exact saved conflicts are
preserved, including their conservative overlap; this UI change does not silently
repair aircraft configuration.

The regression fixture contains aircraft configuration only, with no operational
flight or authentication data. Tests verify complete mapping, lane order, exact
combination occupancy, missing-data messages, D4 markers, A350-only rollout, and
rejection of conflicting pallets and the mutually exclusive FWD 12/13/14 options.

## Scope boundary

The A350 tray contains unassigned loads only. Its dynamic columns are baggage
ULDs, cargo ULDs, mail/other ULDs, and bulk items; categories disappear as their
last item is assigned. SHOW ALL and CONFLICTS filter this remaining load only.
Conflicts use the existing independent placement validator, including occupied
bay resources and bulk capacity. Summary volume comes from configured bulk
positions and current assignments; missing volume is reported as unavailable.
Tray cards reuse the board card component, colours, text and special-load stripes.
Their dimensions are measured from a matching configured board target, with the
smallest currently available occupancy preferred. Alternative target sizes remain
data-driven. No compatible configured target produces a visible configuration
note instead of an invented footprint. AUTOLOAD / MASS OFFLOAD keeps its existing
draft-only behaviour. Other aircraft retain their previous tray.

An A350 with released loads and no published edition initializes its board and
unassigned-load tray when the workflow opens. This is a read-only action: it does
not run AUTOLOAD or publish a plan. The A350 Load Plan section opens expanded;
loading failures remain visible with a retry action. The initial unpublished
state is explicitly unallocated, so publishing stays disabled until all loads
are placed and validated. This fixes the previous circular dependency in which
the only AUTOLOAD button was hidden until a plan already existed.

Live verification used ZZ9350 on 23 October 2026: the initial board displayed all
eight released loads, and an unsaved AUTOLOAD proposal placed both ULD and bulk
loads. No edition was committed. The browser regression test supports repeating
the startup check with a designated released, unpublished A350 test flight via
`E2E_DRAFT_A350_PATH`.

No deployment, merge, push, database write, or migration is included. Extending the
renderer to another aircraft requires a separate validation step and authorization.
