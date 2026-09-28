# C8 — ordered fuel loading schedules CSV

**Draft user guide**

## What this file does

Defines the sequence in which fuel is added to tanks. This file describes loading amounts and order; the separate tank-curve file supplies the volume/arm relationship.

You can upload schedules before or after tank curves. Referenced tanks not yet defined are added as placeholders. Complete their capacities and curves before using calculated loading effects.

## Columns

| Column | What to enter |
|---|---|
| Schedule Name | Required name, up to 100 characters. Repeat it for all steps in that schedule. |
| Specific Gravity | Required positive value, e.g. `0.79`. Repeat for every step. |
| Step | Required whole number: 1, 2, 3… with no gaps or duplicates within a schedule. |
| Tank Code(s) | Required tank code. For multiple tanks use `XTL + XTR`; codes must match the tank definitions. |
| Volume Amount | Fuel volume **added during this step**, in the configured volume unit. |
| Weight Amount | Fuel weight **added during this step**, in the configured weight unit. |

Complete **exactly one** amount column per row. Use the same amount basis for every step of a given schedule; a different schedule may use the other basis. Amounts must be positive. Do not enter cumulative totals in an Amount column.

## Volume-based example

Illustration only, assuming litres:

```csv
Schedule Name,Specific Gravity,Step,Tank Code(s),Volume Amount,Weight Amount
Example Volume Schedule,0.79,1,XTI,1000,
Example Volume Schedule,0.79,2,XTO,500,
```

## Weight-based example

Illustration only, assuming kilograms:

```csv
Schedule Name,Specific Gravity,Step,Tank Code(s),Volume Amount,Weight Amount
Example Weight Schedule,0.80,1,XTI,,800
Example Weight Schedule,0.80,2,XTO,,400
```

The application calculates the counterpart volume/weight, cumulative amount and percentage/ratio. Review any tank-capacity or missing-curve messages before relying on the chart.

## Applying the import

UPLOAD SCHEDULES opens a preview. APPLY SCHEDULE IMPORT adds or replaces schedules matching **Schedule Name + Specific Gravity** in the editable form. Other schedules remain. Use the section SAVE control to persist the result.

The current download may contain your existing schedule rows. Remove or edit those deliberately before upload; it is not necessarily an empty file.
