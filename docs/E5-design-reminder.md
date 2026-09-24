# E5 Fleet/Aircraft Weights - Resolved Design Decision

The E1.2 registration-reference model has been incorporated into E5.

E1.2 preserves crew/pantry-specific rows in `Carrier_Aircraft_Fleet` and creates a separate registration reference row. When existing data is first migrated, the lightest existing weight/index pair is used to initialise that reference row.

The implemented rules are:

- E5 maintains the canonical E1.2 registration reference row.
- Detailed crew/pantry combination rows remain independent and are preserved.
- Fleet Weights stores adjustments and calculates the canonical actual Weight and Index from the E1.2 fleet baseline.
- Individual Aircraft Weights stores the canonical actual Weight and Index directly.
- E1.2 fleet baseline edits recalculate canonical actual values from stored adjustments.
- E1.2 reference-row edits recalculate adjustments while Fleet Weights is active.

This relationship is enforced by the E1.2 and E5 database save functions.
