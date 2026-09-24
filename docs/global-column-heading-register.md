# Global Column Heading Register

The executable register is `src/domain/display-standards.ts`. Screens and generated documents must use its label for every shared data entity.

| Key | Standard heading | Numeric display | Alignment | Unit | Notes |
| --- | --- | --- | --- | --- | --- |
| `index` | Index | 1 decimal | Right | None | Replaces “Index Value”. |
| `indexPerWeightUnit` | Index Per Weight Unit | 5 decimals | Right | None | Replaces “Index per Unit Weight” and “Index / Wt Unit”. |
| `balanceArm` | Balance Arm | N/A | Centre | None | Group heading. |
| `balanceArmCentroid` | Balance Arm Centroid | 3 decimals | Right | Length | May be “Centroid” beneath a Balance Arm group heading. |
| `balanceArmFrom` | From | 3 decimals | Right | Length | Short form requires the Balance Arm group heading. |
| `balanceArmTo` | To | 3 decimals | Right | Length | Short form requires the Balance Arm group heading. |
| `maxWeight` | Max Weight | Whole number | Right | Weight | Replaces “Maximum Weight” as a column heading. |
| `weight` | Weight | Whole number | Right | Weight | Uses the applicable aircraft or carrier unit. |
| `fuelWeight` | Fuel Weight | Whole number | Right | Weight | Uses the applicable aircraft unit. |
| `taxiFuel` | Taxi Fuel | Whole number | Right | Weight | Uses the applicable aircraft unit. |
| `fuelStandardHorizontalArm` | H-Arm | 3 decimals | Right | Length | Approved only for C8 Standard Fuel Loading Schedule. |
| `specificGravity` | Specific Gravity | 3 decimals | Right | None | No unit suffix. |
| `volume` | Volume | 2 decimals | Right | Volume | Uses the applicable aircraft or carrier unit. |
| `maximumVolume` | Maximum Volume | Whole number | Right | Volume | Uses the applicable aircraft unit. |
| `maxSeats` | Max Seats | Whole number | Centre | None | Seat count. |
| `totalSeats` | Total Seats | Whole number | Centre | None | Seat count. |

## Unit presentation

- The stored database code remains `KG`.
- User-facing headings display `Kg`.
- Unit conversion and database validation remain separate from presentation.

## Enforcement

`pnpm check:headings` rejects retired labels in screen components and PDF rulebook generators. `pnpm verify` runs the audit before the normal checks.
