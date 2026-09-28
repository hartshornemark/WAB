# C8 — tank curves CSV

**Draft user guide**

## What this file does

Provides each tank's relationship between fuel volume and balance arm. These points support weight and index calculations at other specific gravities. This is separate from the Standard Fuel Loading table containing SG, Weight and Index.

Upload all tanks in one file or selected tanks only. Tank curves and loading schedules can be uploaded in either order; both must be complete before the loading-effect calculation can use them together.

## Columns

Use the units configured on C1 and shown on C8.

| Column | What to enter |
|---|---|
| Tank Code | Required. One to six letters/numbers, consistently identifying the tank. |
| Tank Name | Optional descriptive name. Keep it consistent for every row of that tank. |
| Maximum Volume | Optional at import: a positive whole number. Supply the actual tank capacity when known. |
| Volume | Required. Whole-number fuel volume, zero or greater. |
| Balance Arm | Required. The arm at this volume, in the aircraft's length unit. Decimals are allowed. |
| Weight | Optional source comparison value; whole number, zero or greater. |
| Index | Optional source comparison value; signed decimals are allowed. |
| Source SG | Optional positive source specific gravity for comparison calculations. |

Volume and Balance Arm are the base data. Weight and Index do not replace them. Use the SG convention expected by C8; do not enter `79` for `0.79`.

Example only, assuming litres and metres:

```csv
Tank Code,Tank Name,Maximum Volume,Volume,Balance Arm,Weight,Index,Source SG
XTI,Inner Tanks,2000,0,20,,,0.79
XTI,Inner Tanks,2000,1000,20.2,,,0.79
XTI,Inner Tanks,2000,2000,20.4,,,0.79
```

Include enough points to cover the volume range used by your schedules. Do not repeat a volume for the same tank. Enter consistent tank name, maximum and source SG values across its rows.

If Maximum Volume is blank, the import uses the existing capacity, or the highest imported volume for a new tank. Check that this is the intended capacity before saving.

## Applying the import

UPLOAD TANK CURVES opens a preview. APPLY IMPORT replaces the curve points for the listed tanks in the editable form. Tanks not in the file and existing By Tank weight entries are retained. Use the section SAVE control to persist the changes.

A schedule may be entered first, but calculations still need the referenced tanks' curves, capacities and the required aircraft formula settings.
